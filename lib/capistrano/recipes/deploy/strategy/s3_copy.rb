require 'capistrano/recipes/deploy/strategy/copy'
require 'erb'


module Capistrano
  module Deploy
    module Strategy
      class S3Copy < Copy

        def initialize(config={})
          super(config)
          @bucket_name = configuration[:aws_releases_bucket]
          raise Capistrano::Error, "Missing configuration[:aws_releases_bucket]" if @bucket_name.nil?
        end

        def check!
          super.check do |d|
            d.local.command("s3cmd")
            d.remote.command("s3cmd")
          end
        end

        # Distributes the file to the remote servers
        def distribute!
          package_path = filename
          package_name = File.basename(package_path)
          s3_push_cmd = "s3cmd put #{package_path} s3://#{bucket_name}/#{rails_env}/#{package_name} 2>&1"

          if configuration.dry_run
            logger.debug s3_push_cmd
          else
            system(s3_push_cmd)
            raise Capistrano::Error, "shell command failed with return code #{$?}" if $? != 0
          end

          run "/usr/bin/s3cmd -c /etc/s3cmd.conf get s3://#{bucket_name}/#{rails_env}/#{package_name} #{remote_filename} 2>&1"
          run "cd #{configuration[:releases_path]} && #{decompress(remote_filename).join(" ")} && rm #{remote_filename}"
          logger.debug "done!"

          build_aws_install_script
        end

        def build_aws_install_script
          template_text = configuration[:aws_install_script]
          template_text = File.read(File.join(File.dirname(__FILE__), "aws_install.sh.erb")) if template_text.nil?
          template_text = template_text.gsub("\r\n?", "\n")
          template = ERB.new(template_text, nil, '<>-')
          output = template.result(self.binding)
          local_output_file = File.join(copy_dir, "aws_install.sh")
          File.open(local_output_file, "w") do  |f|
            f.write(output)
          end
          configuration[:s3_copy_aws_install_cmd] = "s3cmd put #{local_output_file} s3://#{bucket_name}/#{rails_env}/aws_install.sh 2>&1"
        end

        def binding
          super
        end

        def bucket_name
          @bucket_name
        end
      end
    end
  end
end
