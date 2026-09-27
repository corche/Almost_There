Pod::Spec.new do |s|
  s.name = 'alarm_output'
  s.version = '0.1.0'
  s.summary = 'Private arrival alarm output routing.'
  s.description = 'Guards earphone playback and provides speaker output for Almost There.'
  s.homepage = 'https://example.invalid/almost-there'
  s.license = { :type => 'Proprietary' }
  s.author = { 'Almost There' => 'app@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
