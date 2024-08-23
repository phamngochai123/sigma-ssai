Pod::Spec.new do |spec|
  spec.name               = "SSAITracking"
  spec.version            = "1.0.3"
  spec.summary            = "SimgaSSAI Library for iOS apps"
  spec.description        = "TDM SimgaSSAI Library for iOS apps"
  spec.homepage           = "..."
  spec.documentation_url  = "..."
  spec.license            = { :type => "MIT" }
  spec.author             = { "TDM" => "..." }
  spec.source             = { :git => 'https://github.com/phamngochai123/sigma-ssai.git', :tag => "#{spec.version}" }
  spec.swift_version      = "5.3"
  spec.source_files = "SSAITracking/**/*.{h,m.swift}"

  # Supported deployment targets
  spec.ios.deployment_target  = "12.4"

  # Published binaries
  spec.vendored_frameworks = "libs/ProgrammaticAccessLibrary.xcframework"
end