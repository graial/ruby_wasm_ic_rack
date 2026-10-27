# ic_rack: serves a Rack app (anything answering call(env) with
# [status, headers, body]) from the IC HTTP gateway's two methods, in a Ruby
# canister packed by ruby_wasm_builder. Pure Ruby with no dependency, the same
# on the `minimal` and `full` Builds: it names no standard library, no C
# extension and no Encoding constant. rack.input is a small reader of its own
# unless the Application redefines IcRack.input (a StringIO, say).
#
# Taken from the builder's 0.7.0 Challenges (rack_adapter, roda_on_minimal),
# which keep their own copies; this gem moves on its own versions.
#
# A query can't keep a write, so http_request answers only the safe methods
# (GET, HEAD, OPTIONS) and asks the gateway to upgrade everything else to
# http_request_update. An app whose GET writes says so with the response
# header `x-ic-upgrade`, and the query upgrades that too; the header is never
# sent on.
require_relative "ic_rack/version"

module IcRack
  SAFE = %w[GET HEAD OPTIONS].freeze
  UPGRADE = "x-ic-upgrade"

  # rack.input over the body's bytes: what Rack 3 asks of an input stream.
  class Input
    def initialize(bytes)
      @bytes = bytes.b
      @pos = 0
    end

    def read(length = nil, buffer = nil)
      rest = @bytes.byteslice(@pos, @bytes.bytesize - @pos) || "".b
      chunk = length ? rest.byteslice(0, length) : rest
      @pos += chunk.bytesize
      return nil if length && length.positive? && chunk.empty?

      buffer ? buffer.replace(chunk) : chunk
    end

    def gets
      return nil if @pos >= @bytes.bytesize

      stop = @bytes.index("\n", @pos)
      line = @bytes.byteslice(@pos, (stop ? stop + 1 : @bytes.bytesize) - @pos)
      @pos += line.bytesize
      line
    end

    def each
      while (line = gets)
        yield line
      end
    end

    def rewind = @pos = 0
    def close = nil
  end

  module_function

  # rack.input over the body. An Application may redefine it (roda_on_minimal
  # gives a StringIO).
  def input(bytes) = Input.new(bytes)

  def env(req)
    path, query = req[:url].split("?", 2)
    host = header(req, "host").to_s
    env = {
      "REQUEST_METHOD" => req[:method],
      "SCRIPT_NAME" => "",
      "PATH_INFO" => path.to_s.empty? ? "/" : path,
      "QUERY_STRING" => query.to_s,
      "SERVER_NAME" => host.split(":").first.to_s,
      "SERVER_PORT" => "443",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "rack.url_scheme" => "https",
      "rack.input" => input(req[:body]),
      "rack.errors" => $stderr
    }
    req[:headers].each do |name, value|
      key = name.upcase.tr("-", "_")
      key = "HTTP_#{key}" unless %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
      env[key] = env.key?(key) ? "#{env[key]}, #{value}" : value
    end
    env
  end

  def header(req, name) = req[:headers].find { |n, _| n.downcase == name }&.last

  # The gateway's response record from a Rack response. A header's value may
  # be an Array, or lines joined by "\n" (Rack 3): one header each.
  def response(status, headers, body)
    pairs = headers.flat_map do |name, value|
      Array(value).flat_map { |v| v.to_s.split("\n") }.map { |v| [name.to_s.downcase, v] }
    end
    bytes = +"".b
    body.each { |part| bytes << part.b }
    { status_code: Integer(status), headers: pairs, body: bytes, upgrade: nil }
  ensure
    body.close if body.respond_to?(:close)
  end

  def upgrade = { status_code: 200, headers: [], body: "".b, upgrade: true }

  # http_request: the query.
  def query(app, req)
    return upgrade unless SAFE.include?(req[:method])

    status, headers, body = app.call(env(req))
    if headers.keys.any? { |k| k.to_s.downcase == UPGRADE }
      body.close if body.respond_to?(:close)
      return upgrade
    end
    response(status, headers, body)
  end

  # http_request_update: the update, after an upgrade.
  def update(app, req)
    status, headers, body = app.call(env(req))
    response(status, headers.reject { |k, _| k.to_s.downcase == UPGRADE }, body)
  end
end
