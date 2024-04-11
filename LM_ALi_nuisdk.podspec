Pod::Spec.new do |s|

  s.name         = "LM_ALi_nuisdk"
  s.version      = "1.0.0"
  s.summary      = "a li nuisdk "
  s.description  = <<-DESC
                  a li nuisdk
                   DESC

  s.homepage     = "https://github.com/sillker/LM_ALi_nuisdk"
  s.license      = "MIT"
  s.author       = { "sillker" => "269055130@qq.com" }
  s.platform     = :ios, "11.0"
  s.source       = { :git => "https://github.com/sillker/LM_ALi_nuisdk.git", :tag => s.version}
  
  #s.resources = "**/Resources.bundle"
  #s.vendored_frameworks = "**/nuisdk.framework"
  
  #s.resources = "Resources/*.*"
  s.vendored_frameworks = 'nuisdk.framework'

  #s.frameworks = "QuartzCore","Foundation"

  s.library   = "iconv"

end