require File.expand_path('lib/ruby_wasm_ic_rack/version', __dir__)

Gem::Specification.new do |spec|
  spec.name                  = 'ruby_wasm_ic_rack'
  spec.version               = RubyWasmIcRack::VERSION
  spec.authors               = ['graial']
  spec.email                 = ['graial@paglalayag.net']
  spec.summary               = 'Run rack and roda on the ruby.wasm build for IC!'
  spec.description           = 'Use this gem to run rack and roda on the ruby.wasm build for Internet Computer.'
  spec.homepage              = 'https://github.com/graial/ruby_wasm_ic_rack'
  spec.license               = 'MIT'
  spec.platform              = Gem::Platform::RUBY
  spec.required_ruby_version = '>= 3.3.3'
end