Pod::Spec.new do |s|
  s.name             = 'openmuse_native_text_gate'
  s.version          = '0.1.0'
  s.summary          = 'OpenMuse NSView platform integration gate.'
  s.description      = 'Native editable text view used to verify plugin embedding.'
  s.homepage         = 'https://openmuse.io'
  s.license          = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author           = { 'OpenMuse' => 'engineering@openmuse.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
end
