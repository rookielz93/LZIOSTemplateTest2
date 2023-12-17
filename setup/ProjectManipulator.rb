require 'xcodeproj'

module Pod

  class ProjectManipulator
    attr_reader :configurator, :xcodeproj_path, :platform, :remove_demo_target, :string_replacements, :prefix

    def self.perform(options)
      new(options).perform
    end

    def initialize(options)
      @xcodeproj_path = options.fetch(:xcodeproj_path)
      @configurator = options.fetch(:configurator)
      @platform = options.fetch(:platform)
      @remove_demo_target = options.fetch(:remove_demo_project)
      @prefix = options.fetch(:prefix)
    end

    def run
      @string_replacements = {
        "PROJECT_OWNER" => @configurator.user_name,
        "TODAYS_DATE" => @configurator.date,
        "TODAYS_YEAR" => @configurator.year,
        "PROJECT" => @configurator.pod_name,
        "CPD" => @prefix
      }
      replace_internal_project_settings

      @project = Xcodeproj::Project.open(@xcodeproj_path)
      # add_podspec_metadata
      remove_demo_project if @remove_demo_target
      @project.save

      rename_files
      rename_project_folder
    end

    def add_podspec_metadata
      project_metadata_item = @project.root_object.main_group.children.select { |group| group.name == "Podspec Metadata" }.first
      project_metadata_item.new_file "../" + @configurator.pod_name  + ".podspec"
      project_metadata_item.new_file "../README.md"
      project_metadata_item.new_file "../LICENSE"
    end

    def remove_demo_project
      app_project = @project.native_targets.find { |target| target.product_type == "com.apple.product-type.application" }

      # Remove the implicit dependency on the app
      app_project.remove_from_project

      # Remove the references in xcode
      project_app_group = @project.root_object.main_group.children.select { |group| group.display_name.end_with? @configurator.pod_name }.first
      project_app_group.remove_from_project

      # Remove the product reference
      product = @project.products.select { |product| product.path == @configurator.pod_name.app }.first
      product.remove_from_project

      # Remove the actual folder + files for both projects
      `rm -rf templates/ios/PROJECT`
    end

    def project_folder
      File.dirname @xcodeproj_path
    end

    def rename_files
      # print("project_folder: " + project_folder + "\n")
      # print("pwd: " + Dir.pwd() + "\n")
      # shared schemes have project specific names
      scheme_path = project_folder + "/PROJECT.xcodeproj/xcshareddata/xcschemes/"
      File.rename(scheme_path + "PROJECT.xcscheme", scheme_path +  @configurator.pod_name + ".xcscheme")

      # rename xcproject
      File.rename(project_folder + "/PROJECT.xcodeproj", project_folder + "/" +  @configurator.pod_name + ".xcodeproj")

      unless @remove_demo_target
        # change Main.storyboard content prefixes
        ["Base.lproj/Main.storyboard"].each do |file|
          path = project_folder + "/PROJECT/" + file
          next unless File.exist? path
 
          File.open(path, "r:utf-8") do |lines|     #r:utf-8表示以utf-8编码读取文件，要与当前代码文件的编码相同
            buffer = lines.read.gsub("CPD", prefix) #将文件中所有的CPD替换为prefix，并将替换后文件内容赋值给buffer
            File.open(path, "w"){|l|                #以写的方式打开文件，将buffer覆盖写入文件
              l.write(buffer)
            }
          end
        end

        # change app file prefixes
        ["CPDAppDelegate.h", "CPDAppDelegate.m", 
        "Business/Pages/Home/CPDHomeViewController.h", 
        "Business/Pages/Home/CPDHomeViewController.m", 
        "Business/Pages/Test/CPDTestPage.h", 
        "Business/Pages/Test/CPDTestPage.m"].each do |file|
          before = project_folder + "/PROJECT/" + file
          next unless File.exist? before

          after = project_folder + "/PROJECT/" + file.gsub("CPD", prefix)
          File.rename before, after
        end

        # rename project related files
        ["PROJECT-Info.plist", "PROJECT-Prefix.pch", "PROJECT.entitlements"].each do |file|
          before = project_folder + "/PROJECT/" + file
          next unless File.exist? before

          after = project_folder + "/PROJECT/" + file.gsub("PROJECT", @configurator.pod_name)
          File.rename before, after
        end
      end
    end

    def rename_project_folder
      if Dir.exist? project_folder + "/PROJECT"
        File.rename(project_folder + "/PROJECT", project_folder + "/" + @configurator.pod_name)
      end
    end

    def replace_internal_project_settings
      Dir.glob(project_folder + "/**/**/**/**").each do |name|
        next if Dir.exist? name
        text = File.read(name)

        for find, replace in @string_replacements
            text = text.gsub(find, replace)
        end

        File.open(name, "w") { |file| file.puts text }
      end
    end

  end

end
