Pod::Spec.new do |s|
  s.name             = 'openmuse_dsh_plugin'
  s.version          = '0.1.0'
  s.summary          = 'OpenMuse DSH loopback WebView plugin.'
  s.description      = 'Embeds the local DSH sidecar UI in a constrained WKWebView.'
  s.homepage         = 'https://openmuse.io'
  s.license          = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author           = { 'OpenMuse' => 'engineering@openmuse.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
end
