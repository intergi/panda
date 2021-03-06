namespace :dev do
  desc "Sets up dependencies and configures nginx, which should be running correctly out of the box once installed!"
  task :setup => [:install_libjpeg, :install_gd, :nginx, :panda_config_wizard, :auto_bootstrap] do
    puts "Setup complete!"
  end

  task :install_libjpeg do
    if !File.writable?("/")
      warn "Please run this command as root!"
      exit
    end
    system("mkdir -p ~/src; chmod 777 ~/src")
    Dir.chdir("#{ENV['HOME']}/src")
    if File.exists?("jpeg-6b/Makefile")
      puts "Already installed libjpeg. (to reinstall please `rm -rf ~/src/jpeg-6b`)"
    else
      puts "Installing libjpeg..."
      system("curl -O ftp://ftp.aai.ee/pub/unix/jpegsrc.v6b.tar.gz; tar zxvf jpegsrc.v6b.tar.gz") unless File.exists?("jpegsrc.v6b.tar.gz")
      system("sudo mkdir -p /usr/local/man/man1/")
      system("cd jpeg-6b; ./configure '--with-jpeg=/usr/local' '--with-png=/usr/local' '--with-zlib-dir=/usr/local' && make && sudo make install && sudo make install-lib; cd ..")
    end
  end

  task :install_gd do
    if !File.writable?("/")
      warn "Please run this command as root!"
      exit
    end
    # Install gd2. apt-get, port, whatever works for your system
    installer = `which port`.chomp
    installer = `which apt-get`.chomp if installer == ''
    # system("sudo env PATH=$PATH \"#{installer}\" install gd2 -y")
    system("sudo env PATH=$PATH \"#{installer}\" install ffmpeg -y")

    # More gd stuff
    system("mkdir -p ~/src; chmod 777 ~/src")
    Dir.chdir("#{ENV['HOME']}/src")
    if File.exists?("gd-2.0.35/Makefile")
      puts "Already installed gd (to reinstall please `rm -rf ~/src/gd-2.0.35`)"
    else
      puts "Installing gd..."
      system("curl -O http://www.libgd.org/releases/gd-2.0.35.tar.gz; tar zxvf gd-2.0.35.tar.gz") unless File.exists?("gd-2.0.35.tar.gz")
      system("cd gd-2.0.35 && ./configure && make && sudo make install && cd ..")
    end
  end

  desc "Install and Configure nginx."
  task :nginx => [:"nginx:install", :"nginx:configure"]

  namespace :nginx do
    desc "Install nginx with http-upload-progress support."
    task :install do
      if !File.writable?("/")
        warn "Please run this command as root!"
        exit
      end

      system("mkdir -p ~/src; chmod 777 ~/src")
      Dir.chdir("#{ENV['HOME']}/src")

      puts "Installing nginx..."
      # Installs PCRE, whatever that is. Seems to be a dependency for nginx though.
      if File.exists?("pcre-7.7/Makefile")
        puts "Already installed PCRE (to reinstall please `rm -rf ~/src/pcre-7.7`)"
      else
        puts "Installing PCRE..."
        system("curl -O http://ftp.exim.llorien.org/pcre/pcre-7.7.tar.gz; tar xvfz pcre-7.7.tar.gz") unless File.exists?("pcre-7.7.tar.gz")
        system("cd pcre-7.7; ./configure --prefix=/usr/local && make && sudo make install; cd ..")
      end

      # Installs nginx with http-upload-progress support.
      if File.exists?("nginx-0.7.65/Makefile")
        puts "Already installed nginx (to reinstall please `rm -rf ~/src/nginx-0.7.65`)"
      else
        system("wget http://github.com/masterzen/nginx-upload-progress-module/tarball/v0.8; tar xvfz masterzen-nginx-upload-progress-module-2bf172d.tar.gz") unless File.exists?("masterzen-nginx-upload-progress-module-2bf172d.tar.gz")
        $UPM = File.expand_path('masterzen-nginx-upload-progress-module-2bf172d')
        system("curl -O http://nginx.org/download/nginx-0.7.65.tar.gz; tar xvfz nginx-0.7.65.tar.gz") unless File.exists?("nginx-0.7.65.tar.gz")
        system("cd nginx-0.7.65; ./configure --prefix=/usr/local --with-http_ssl_module --add-module=#{$UPM} && make && sudo make install; cd ..")
      end

      # If /usr/local/sbin is not in $PATH, notify the user that they need it in their path.
      unless ENV['PATH'].split(':').include?('/usr/local/sbin')
        puts "Your PATH needs to include `/usr/local/sbin'. Please add this to your path (~/.bash_profile OR ~/.profile, and ~/.bashrc) and then hit ENTER."
        $stdin.readline
        ENV['PATH'] << '/usr/local/sbin'
      end
      Dir.chdir(RAILS_ROOT)

      Rake::Task["dev:nginx:restart"].invoke
    end

    desc "Configure nginx for me automatically."
    task :configure do
      if !File.writable?("/")
        warn "Please run this command as root!"
        exit
      end

      nginx_config = File.read('/usr/local/conf/nginx.conf')
      if nginx_config =~ /proxy_pass http:\/\/127.0.0.1:4000;/ && nginx_config =~ /track_uploads proxied 30s;/
        puts "Nginx is already configured."
      else
        puts "Configuring nginx..."

        $panda_domain = get_input("Enter the domain this Panda should be accessible at")

        # Open textmate to configure nginx: open the real config and the sample.
        nginx_config = File.read("lib/tasks/dev-setup-sample-configs/nginx.conf")
        nginx_config.gsub!(/HOSTNAME/, $panda_domain)
        File.open('/usr/local/conf/nginx.conf', 'w') {|f| f << nginx_config }
        # Have user hit ENTER when they have nginx configured...

        Rake::Task["dev:nginx:restart"].invoke
      end
    end

    desc "Just starts or restarts nginx properly."
    task :restart do
      nginx_pid = `ps -A|grep nginx`.match(/^\D*(\d+)/)[1] rescue nil
      if nginx_pid
        puts "Restarting nginx..."
        system("sudo kill -HUP #{nginx_pid}")
      else
        puts "Starting nginx..."
        system("sudo nginx")
      end
    end
  end

  desc "Answer questions in a wizard to write out your Panda configuration."
  task :panda_config_wizard do
    $api_key = get_input("Please enter an API key for this Panda installation. (Record it somewhere to use in your API implementation)")
    # private tmp path is okay, but it needs to exist and be writable
    system("sudo mkdir -p /var/tmp/videos; sudo chmod 777 /var/tmp/videos")
    $using_s3 = get_input("Will you be using [S]3 or [F]ilesystem? (S/F)")
    if $using_s3 == 'S'
      $s3_bucket = get_input("Enter the S3 Bucket you'll be using") # S3_BUCKET
    else
      $videos_domain = $panda_domain || get_input("Enter the domain this Panda should be accessible at")
    end
    $access_key_id = get_input("Your AWS access key")
    $secret_access_key = get_input("Your AWS secret key")
    $sdb_prefix = get_input("An optional prefix to your Panda domains on SDB (Enter for none)")
    $state_update_url = get_input("The URL Panda should ping with notification updates, such as encoding events (use :video_file_id for the video id)")
    puts "Configuring Panda..."
    panda_config = File.read('config/panda_init.rb.example')
    panda_config.gsub!(/SECRET_KEY_FOR_PANDA_API/, $api_key)
    panda_config.gsub!(/'USE_S3'/, (($using_s3 == 'S' ? 'true' : 'false')))
    panda_config.gsub!(/S3_BUCKET/, $s3_bucket) if $s3_bucket
    panda_config.gsub!(/VIDEOS_DOMAIN/, $videos_domain)
    panda_config.gsub!(/AWS_ACCESS_KEY/, $access_key_id)
    panda_config.gsub!(/AWS_SECRET_ACCESS_KEY/, $secret_access_key)
    panda_config.gsub!(/SDBPREFIX/, $sdb_prefix)
    panda_config.gsub!(/STATE_UPDATE_URL/, $state_update_url)
    ffmpeg_bin = `which ffmpeg`.chomp
    panda_config.gsub!(/\$FFMPEG = '.*'$/, "$FFMPEG = '#{ffmpeg_bin}'")
    File.open('config/panda_init.rb', 'w') {|f| f << panda_config }
  end

  task :auto_bootstrap do
    # Because it has to re-load everything after configuration to work correctly.
    system("rake dev:bootstrap")
  end

  task :bootstrap do
    system("./script/bootstrap")
  end
end


desc "Starts the extra daemons"
task :start_daemons do
  encoder_res = `merb -r bin/encoder.rb -d -p 5001`
  encoder_pid = encoder_res.gsub(/\D/,'').to_i
  `echo #{encoder_pid} > log/encoder.pid`
  puts "Started encoder."
  notifier_res = `merb -r bin/notifier.rb -d -p 5002`
  notifier_pid = notifier_res.gsub(/\D/,'').to_i
  `echo #{notifier_pid} > log/notifier.pid`
  puts "Started notifier."
end

desc "Stops the extra daemons"
task :stop_daemons do
  encoder_pid = `cat log/encoder.pid`.chomp
  notifier_pid = `cat log/notifier.pid`.chomp
  `kill -INT #{encoder_pid} & rm log/encoder.pid`
  puts "Stopped encoder."
  `kill -INT #{notifier_pid} & rm log/notifier.pid`
  puts "Stopped notifier."
end


def get_input(msg)
  $stdout << "#{msg}: "
  $stdout.flush
  return $stdin.readline.dup.chomp # SECRET_KEY_FOR_PANDA_API
end
