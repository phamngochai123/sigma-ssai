Pod::Spec.new do |spec|
  spec.name               = "SSAITracking"
  spec.version            = "1.0.4"
  spec.summary            = "SimgaSSAI Library for iOS apps"
  spec.description        = "TDM SimgaSSAI Library for iOS apps"
  spec.homepage           = "https://github.com/sigmaott/sigma-ssai-avplayer-sdk"
  spec.documentation_url  = "https://github.com/sigmaott/sigma-ssai-avplayer-sdk"
  spec.license            = { :type => "MIT" }
  spec.author             = { "TDM" => "multimediathudojsc@gmail.com" }
  spec.source             = { :git => 'https://github.com/phamngochai123/sigma-ssai.git', :tag => "#{spec.version}" }
  spec.swift_version      = "5.3"
  spec.source_files = "SSAITracking/**/*.{h,m,swift}"

  # Supported deployment targets
  spec.ios.deployment_target  = "12.4"

  # Published binaries
  spec.vendored_frameworks = "libs/ProgrammaticAccessLibrary.xcframework"
end