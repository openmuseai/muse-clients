Pod::Spec.new do |s|
  s.name             = 'openmuse_file_viewer'
  s.version          = '0.1.0'
  s.summary          = 'OpenMuse local image and PDF viewer plugin.'
  s.description      = <<-DESC
Sandboxed WKWebView surface for local image and PDF resources.
                       DESC
  s.homepage         = 'https://openmuse.io'
  s.license          = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author           = { 'OpenMuse' => 'engineering@openmuse.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
end
