# ic_rack

Serve a [Rack](https://github.com/rack/rack) app from a Ruby canister on the
Internet Computer, through the IC HTTP gateway. For canisters packed by
[ruby_wasm_builder](https://gitlab.com/phrug/ruby_wasm_builder) from 0.7.0.

Pure Ruby, no dependencies. It works the same on the `minimal` and `full`
Builds: it names no standard library, no C extension and no `Encoding`
constant.

## Carrying it

A canister has no `bundle install`. Carry the gem's files in your Application,
as you carry Rack:

```bash
gem fetch ic_rack && gem unpack ic_rack-*.gem
cp -r ic_rack-*/lib my_app/vendor/ic_rack
```

```ruby
# app.rb
$LOAD_PATH.unshift(File.join(__dir__, "vendor/ic_rack"))
require "ic_rack"
```

To move to a newer version, unpack it and copy its `lib/` again.

## Declaring and serving the gateway's methods

From ruby_wasm_builder 0.8.0, one word in `ic-interface.rb` declares the
gateway's types and both methods:

```ruby
# ic-interface.rb
http_gateway
```

On 0.7.0, write them out (this is what the word declares):

```ruby
type :HeaderField, Tuple[Text, Text]
type :HttpRequest, record(method: Text, url: Text, headers: Vec[:HeaderField], body: Blob,
                          certificate_version: Opt[Nat16])
type :HttpUpdateRequest, record(method: Text, url: Text, headers: Vec[:HeaderField], body: Blob)
type :HttpResponse, record(status_code: Nat16, headers: Vec[:HeaderField], body: Blob, upgrade: Opt[Bool])

query  :http_request,        takes: [:HttpRequest],       returns: :HttpResponse
update :http_request_update, takes: [:HttpUpdateRequest], returns: :HttpResponse
```

Then hand both to your app:

```ruby
# app.rb
APP = ->(env) { [200, { "content-type" => "text/plain" }, ["hello from #{env['PATH_INFO']}"]] }

def http_request(req) = IcRack.query(APP, req)
def http_request_update(req) = IcRack.update(APP, req)
```

## What it does

- **The env:** `REQUEST_METHOD`, `PATH_INFO`, `QUERY_STRING`, `SERVER_NAME`
  (from `host`), `SERVER_PORT` 443, `rack.url_scheme` `https`, every header as
  `HTTP_*` (`CONTENT_TYPE` and `CONTENT_LENGTH` as Rack names them), a repeated
  header joined with `, `, and `rack.input` over the body.
- **The response:** a header whose value is an Array, or lines joined by
  `"\n"` (Rack 3), goes out as one header each, so two `set-cookie` headers
  arrive as two. The body is joined and closed.
- **Upgrades.** The gateway calls `http_request` as a query, and a query keeps
  nothing it writes. So `IcRack.query` answers only `GET`, `HEAD` and `OPTIONS`
  and asks the gateway to upgrade everything else, which then calls
  `http_request_update` through consensus. A `GET` that writes says so with the
  response header `x-ic-upgrade` (any value); the query upgrades it, and the
  header is never sent on.
- **`rack.input`** is a small reader of its own (`read`, `gets`, `each`,
  `rewind`). For a `StringIO`, as Rack's own servers give, redefine
  `IcRack.input`:

  ```ruby
  module IcRack
    def self.input(bytes) = StringIO.new(bytes.b)
  end
  ```

## On the `minimal` Build

Rack and Roda need four libraries `minimal` lacks: `Encoding::UTF_8` and its
two siblings, `date` (only because `time` requires it), `strscan` and
`stringio`. The [`ic_minimal`](../ic_minimal) gem carries pure-Ruby stand-ins
for them, for a `minimal` canister only. `ic_rack` itself needs none of them.

Carry only the files of Rack your routes load, and check every carried file's
magic comment: `minimal` knows only `utf-8`, `us-ascii` and `ascii-8bit` by
those names, and Rack 3.1's `rack/utils.rb` says `# encoding: binary`, which
traps the install. Change that word to `ascii-8bit`.

## Not yet

- **Certified responses.** Until the canister certifies its replies, the
  gateway refuses a plain query's reply on the certified domain
  (`<id>.icp0.io`) and serves it on `<id>.raw.icp0.io`. An upgraded request is
  served on either. So a public page is served raw, or by upgrading every
  `GET` (one update per page view).
- File uploads (Tempfile) and streaming responses.

## Development

The gem lives in the ruby_wasm_builder repository, `gems/ic_rack/`. Its specs
are in that repository's `spec/gems/`, and run with the builder's suite
(`bundle exec rspec`), including the 0.7.0 `rack_adapter` and `roda_on_minimal`
Scripts played with this gem's files in place of the Challenges' own copies.

MIT licensed.
