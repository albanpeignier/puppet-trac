# Each trac is configured with the following files :
#
# * /var/lib/trac/<project>/conf/trac.ini
# * /etc/trac/trac.ini
# * /etc/trac/trac.defaults
#
# These files are defined into :
#
# * templates/trac/trac.ini
# * files/trac/trac.ini.<project> (customize this file)
# * files/trac/trac.ini (global settings)
# * files/trac/trac.defaults (do not modify, generated by trac)
class trac {
  include apache2
  include apache2::auth::pam
  include apt::tryphon

  package { trac: }

  package { trac-git: 
    ensure => "0.0.20100513-2~bpo50+1",
    require => Apt::Preferences[trac-git]
  }

  apt::preferences { trac-git:
    package => trac-git, 
    pin => "release a=lenny-backports",
    priority => 999
  }

  # Directory to store all trac projects
  file { "/var/lib/trac":
    ensure => directory
  }

  # Contains trac.ini generated by trac
  file { "/etc/trac/trac.defaults":
    source => "puppet:///trac/trac.defaults",
    require => Package[trac]
  }

  # Customize settings for all projects
  file { "/etc/trac/trac.ini":
    source => ["puppet:///files/trac/trac.ini", "puppet:///trac/trac.ini"],
    require => [Package[trac], File["/etc/trac/trac.defaults"]]
  }

  file { ["/usr/share/trac/hooks", "/usr/share/trac", "/usr/share/trac/templates"]: 
    ensure => directory
  }

  # Hook script use to update trac tickets with git commit messsages
  file { "/usr/share/trac/hooks/git-post-receive-hook":
    source => "puppet:///trac/git-post-receive-hook",
    mode => 755
  }

  # src group needs to update trac database
  sudo::user_line { "trac-git-post-receive-hook":
    line => "%src	ALL=(www-data) NOPASSWD: /usr/share/trac/hooks/git-post-receive-hook",
    require => File["/usr/share/trac/hooks/git-post-receive-hook"]
  }

  file { ["/var/www/trac/cgi-bin/trac.cgi", "/var/www/trac/cgi-bin/trac.fcgi"]:
    mode => 755
  }

  define project($repository_path = '', $description = '', $config = '') {
    include trac

    $real_repository_path = $repository_path ? {
        '' => "/srv/git/$name",
        default => $repository_path
    }

    # Directory to store the trac project
    file { "/var/lib/trac/$name":
      ensure => directory,
      mode => 2775,
      group => www-data
    }

    # Create the trac project
    exec { "trac-initenv-$name":
      # Add a chmod -R g+w to fix permissions
      command => "trac-admin /var/lib/trac/$name initenv $name sqlite:db/trac.db git file://$real_repository_path && chmod -R g+w /var/lib/trac/$name/*",
      user => "www-data",
      group => "www-data",
      creates => "/var/lib/trac/$name/db/trac.db",
      require => [File["/var/lib/trac/$name"], Package[trac-git]]
    }

    $real_config = $config ? {
      '' => "files/trac/trac.ini.$name",
      default => $config
    }

    # Install a trac.ini file for each project
    #
    # This file contains generated values and then the content of files/trac/trac.ini.$name
    file { "/var/lib/trac/$name/conf/trac.ini":
      owner => "www-data",
      group => "www-data",
      content => template("trac/trac.ini"),
      require => [Exec["trac-initenv-$name"], File["/etc/trac/trac.ini"]]
    }

    # Should be executed only by the first project
    exec { "tracadmin-deploy-$name":
      command => "trac-admin /var/lib/trac/$name deploy /var/www/trac && chmod +x /var/www/trac/cgi-bin/trac.cgi /var/www/trac/cgi-bin/trac.fcgi",
      creates => "/var/www/trac",
      require => Exec["trac-initenv-$name"]
    }
  }


  # Add TRAC_ADMIN permission to user in a given project (using trac-admin)
  define admin($project, $user) {
    $project_directory = "/var/lib/trac/$project"
    exec { "tracadmin-$project-add-admin-$user":
      command => "trac-admin $project_directory permission add $user TRAC_ADMIN",
      # 'permission list $user' doesn't return TRAC_ADMIN but detailled privilegies
      unless => "trac-admin $project_directory permission list | grep '^$user.*TRAC_ADMIN'",
      user => "www-data",
      require => Exec["trac-initenv-$project"]
    }
  }

  file { "/usr/local/bin/trac-robotstxt":
    source => "puppet:///trac/trac-robotstxt",
    mode => 755
  }

  file { ["/usr/share/trac/plugins", "/var/cache/trac"]:
    ensure => directory,
    require => Package[trac]
  }

  define plugin($egg, $url) {
    exec { "install-trac-plugin-$name":
      command => "wget -O /usr/share/trac/plugins/$egg $url",
      creates => "/usr/share/trac/plugins/$egg",
      require => File["/usr/share/trac/plugins"]
    }
  }

}


# Trac instances are available on
#
#   http://<host>/trac/<project>/
#
# Authentication is available by visiting :
#
#   http://<host>/trac/<project>/login
class trac::www::basic {
  include trac
  include apache2::fcgid

  apache2::confd_file { trac:
    source => "puppet:///trac/apache2.conf",
    require => [File["/var/lib/trac"], Package[libapache2-mod-fcgid]]
  }
}

class trac::plugin::sitemap {
  trac::plugin { tracsitemap:
    egg => "TracSitemap-1.0-py2.5.egg",
    url => "http://trac-hacks.org/attachment/wiki/TracSitemapPlugin/TracSitemap-1.0-py2.5.egg?format=raw"
  }
}

class trac::plugin::batchmodify {
  trac::plugin { batchmodify: 
    egg => "BatchModify-0.8.0_trac0.11-py2.5.egg",
    url => "http://trac-hacks.org/export/9801/batchmodifyplugin/0.11/tags/BatchModify-0.8.0_trac0.11-py2.5.egg"
  }
}
