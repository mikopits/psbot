Gem::Specification.new do |spec|
  spec.name           = 'psbot'
  spec.version        = '0.1.0'
  spec.authors        = ['Eric Furugori']
  spec.email          = ['mikopits@gmail.com']
  spec.summary        = %q{Ruby chatbot for Pokemon Showdown}
  spec.description    = %q{An extensible chatbot for Pokemon Showdown}
  #spec.homepage       = 'n/a'
  spec.license        = "MIT"
  spec.required_ruby_version = '>= 1.9.1'
  spec.files          = Dir['LICENSE', 'README.md', '.yardopts', '{docs,lib,examples}/**/*']
  spec.test_files     = ['test/test.rb']
  spec.has_rdoc = "yard"
end
