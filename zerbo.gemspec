# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "zerbo/version"

Gem::Specification.new do |s|
  s.name        = "zerbo"
  s.version     = Zerbo::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Tim Pope"]
  s.email       = "ruby@tpo"+'pe.org'
  s.homepage    = "http://github.com/tpope/zerbo"
  s.summary     = "Zeo Personal Sleep Coach Ruby Interface"
  s.description = "Build a serial cable for your Zeo and interface with it with this library."

  s.rubyforge_project = "zerbo"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency("ruby-serialport")
end
