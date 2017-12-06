
Pod::Spec.new do |s|

  s.name         = "LPMHookUtils"
  s.version      = "0.0.2"
  s.summary      = "LPMHookUtils."
  s.description  = <<-DESC
                    LPMHookUtils which is used to hook the objective-c method.
                   DESC

  s.homepage     = "https://github.com/JaylonPan/LPMHookUtils.git"
  s.source       = {:git => "https://github.com/JaylonPan/LPMHookUtils.git", :tag => "#{s.version}"}
  s.license      = { :type => 'MIT', :text => <<-LICENSE
                      Copyright 2017
                      JaylonPan
                    LICENSE
                    }
  s.author       = { "Jaylon" => "269003942@qq.com" }
  s.platform     = :ios, "8.0"
  s.source_files  = "LPMHookUtils.{h,m}"
  s.header_dir = 'LPMHookUtils'

end

