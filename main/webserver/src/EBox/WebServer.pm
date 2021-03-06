# Copyright (C) 2008-2013 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
use strict;
use warnings;

package EBox::WebServer;

use base qw(EBox::Module::Service EBox::SyncFolders::Provider);

use EBox::Global;
use EBox::Gettext;
use EBox::SyncFolders::Folder;
use EBox::Service;

use EBox::Exceptions::External;
use EBox::Exceptions::Sudo::Command;
use EBox::Users::User;
use EBox::WebServer::PlatformPath;
use EBox::WebServer::Model::GeneralSettings;
use EBox::WebServer::Model::VHostTable;
use EBox::WebServer::Composite::General;

use Error qw(:try);
use Perl6::Junction qw(any);

use constant VHOST_PREFIX => 'ebox-';
use constant CONF_DIR => EBox::WebServer::PlatformPath::ConfDirPath();
use constant PORTS_FILE => CONF_DIR . '/ports.conf';
use constant ENABLED_MODS_DIR => CONF_DIR . '/mods-enabled/';
use constant AVAILABLE_MODS_DIR => CONF_DIR . '/mods-available/';

use constant LDAP_USERDIR_CONF_FILE => 'ldap_userdir.conf';
use constant SITES_AVAILABLE_DIR => CONF_DIR . '/sites-available/';
use constant SITES_ENABLED_DIR => CONF_DIR . '/sites-enabled/';
use constant GLOBAL_CONF_DIR => CONF_DIR . '/conf.d/';

use constant VHOST_DFLT_FILE => SITES_AVAILABLE_DIR . 'default';
use constant VHOST_DFLTSSL_FILE => SITES_AVAILABLE_DIR . 'default-ssl';
use constant SSL_DIR => CONF_DIR . '/ssl/';

# Constructor: _create
#
#        Create the web server module.
#
# Overrides:
#
#        <EBox::Module::Service::_create>
#
# Returns:
#
#        <EBox::WebServer> - the recently created module.
#
sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'webserver',
                                      printableName => __('Web Server'),
                                      @_);
    bless($self, $class);
    return $self;
}

# Method: usedFiles
#
#	Override EBox::Module::Service::usedFiles
#
sub usedFiles
{
    my ($self) = @_;

    my $files = [
    {
        'file' => PORTS_FILE,
        'module' => 'webserver',
        'reason' => __('To set webserver listening port.')
    },
    {
        'file' => VHOST_DFLT_FILE,
        'module' => 'webserver',
        'reason' => __('To configure default virtual host.')
    },
    {
        'file' => VHOST_DFLTSSL_FILE,
        'module' => 'webserver',
        'reason' => __('To configure default SSL virtual host.')
    },
    {
        'file' => AVAILABLE_MODS_DIR . LDAP_USERDIR_CONF_FILE,
        'module' => 'webserver',
        'reason' => __('To configure the per-user public_html directory.')
    }
    ];

    my $vHostModel = $self->model('VHostTable');
    foreach my $id (@{$vHostModel->ids()}) {
        my $vHost = $vHostModel->row($id);
        # access to the field values for every virtual host
        my $vHostName = $vHost->valueByName('name');
        my $destFile = SITES_AVAILABLE_DIR . VHOST_PREFIX . $vHostName;
        push(@{$files}, { 'file' => $destFile, 'module' => 'webserver',
                          'reason' => "To configure $vHostName virtual host." });
    }

    return $files;
}

# Method: actions
#
#       Override EBox::Module::Service::actions
#
sub actions
{
    return [
    {
        'action' => __('Enable Apache LDAP user module'),
        'module' => 'webserver',
        'reason' => __('To fetch home directories from LDAP.')
    },
    {
        'action' => __('Enable Apache SSL module'),
        'module' => 'webserver',
        'reason' => __('To serve pages over HTTPS.')
    },
    {
        'action' => __('Remove apache2 init script link'),
        'reason' => __('Zentyal will take care of starting and stopping ' .
                       'the services.'),
        'module' => 'webserver'
    }
    ];
}

# Method: initialSetup
#
# Overrides:
#
#        <EBox::Module::Base::initialSetup>
#
sub initialSetup
{
    my ($self, $version) = @_;

    # Create default rules and services
    # only if installing the first time
    unless ($version) {
        my $firewall = $self->global()->modInstance('firewall');

        my $port = $firewall->requestAvailablePort('tcp', 80, 8080);
        $firewall->addInternalService(
                'name'            => 'webserver',
                'printableName'   => __('Web Server'),
                'description'     => __('Zentyal Web Server'),
                'protocol'        => 'tcp',
                'sourcePort'      => 'any',
                'destinationPort' => $port,
        );

        $firewall->saveConfigRecursive();

        # Set port in the model
        my $settings = $self->model('GeneralSettings');
        $settings->setValue(port      => $port);
        $settings->setValue(enableDir => EBox::WebServer::Model::GeneralSettings::DefaultEnableDir());
    }
}

# Method: depends
#
#     WebServer depends on modules that have webserver in enabledepends.
#
# Overrides:
#
#        <EBox::Module::Base::depends>
#
sub depends
{
    my ($self) = @_;

    my $dependsList = $self->SUPER::depends();

    my $global = EBox::Global->getInstance(1);
    foreach my $mod (@{ $global->modInstancesOfType('EBox::Module::Service') }) {
        next if ($self eq $mod);
        my $deps = $mod->enableModDepends();
        next unless $deps;
        if ($self->name() eq any(@$deps)) {
            push(@{$dependsList}, $mod->name());
        }
    }

    return $dependsList;
}

# to avoid circular restore dependencies cause by depends override
sub restoreDependencies
{
    my ($self) = @_;
    my $dependsList = $self->SUPER::depends();
    return $dependsList;
}

# Method: menu
#
#        Show the Web Server menu entry.
#
# Overrides:
#
#        <EBox::Module::menu>
#
sub menu
{
      my ($self, $root) = @_;

      my $item = new EBox::Menu::Item(name  => 'WebServer',
                                      icon  => 'webserver',
                                      text  => $self->printableName(),
                                      separator => 'Office',
                                      url   => 'WebServer/Composite/General',
                                      order => 570
                                     );
      $root->add($item);
}

#  Method: _daemons
#
#   Override <EBox::Module::Service::_daemons>
#

sub _daemons
{
    return [
        {
            'name' => 'apache2',
            'type' => 'init.d',
            'pidfiles' => ['/var/run/apache2.pid'],
        }
    ];
}

# Method: virtualHosts
#
#       Return a list of current virtual hosts.
#
# Returns:
#
#       array ref - containing each element a hash ref with these three
#       components:
#
#       - name - String the virtual's host name
#       - ssl - [disabled|allowssl|forcessl]
#       - enabled - Boolean if it is currently enabled or not
#
sub virtualHosts
{
    my ($self) = @_;

    my $vHostModel = $self->model('VHostTable');
    my @vHosts;
    foreach my $id (@{$vHostModel->ids()}) {
        my $rowVHost = $vHostModel->row($id);
        push (@vHosts, {
                        name => $rowVHost->valueByName('name'),
                        ssl => $rowVHost->valueByName('ssl'),
                        enabled => $rowVHost->valueByName('enabled'),
                       });
    }

    return \@vHosts;
}

# Group: Static public methods

# Method: VHostPrefix
#
#     Get the virtual host prefix used by all virtual host created by
#     Zentyal.
#
# Returns:
#
#     String - the prefix
#
sub VHostPrefix
{
    return VHOST_PREFIX;
}

# Group: Private methods

# Method: _setConf
#
#        Regenerate the webserver configuration.
#
# Overrides:
#
#        <EBox::Module::Service::_setConf>
#
sub _setConf
{
    my ($self) = @_;

    my $vHostModel = $self->model('VHostTable');
    my $vhosts    = $vHostModel->virtualHosts();
    my $hostname      = $self->_fqdn();
    my $hostnameVhost = delete $vhosts->{$hostname};

    $self->_setPort();
    $self->_setUserDir();
    $self->_setDfltVhost($hostname, $hostnameVhost);
    $self->_setDfltSSLVhost($hostname, $hostnameVhost);
    $self->_checkCertificate();
    $self->_setVHosts($vhosts, $hostnameVhost);
}

# Set up the listening port
sub _setPort
{
    my ($self) = @_;

    my $generalConf = $self->model('GeneralSettings');

    $self->writeConfFile(PORTS_FILE, "webserver/ports.conf.mas",
                         [
                           portNumber => $generalConf->portValue(),
                           sslportNumber =>  $generalConf->sslPort(),
                         ],
                        );
}

# Set up default vhost
sub _setDfltVhost
{
    my ($self, $hostname, $hostnameVhost) = @_;

    my $generalConf = $self->model('GeneralSettings');

    # Overwrite the default vhost file
    $self->writeConfFile(VHOST_DFLT_FILE, "webserver/default.mas",
                         [
                           hostname => $hostname,
                           portNumber => $generalConf->portValue(),
                           sslportNumber =>  $generalConf->sslPort(),
                           hostnameVhost => $hostnameVhost,
                         ],
                        );
}

# Set up default-ssl vhost
sub _setDfltSSLVhost
{
    my ($self, $hostname, $hostnameVhost) = @_;

    my $generalConf = $self->model('GeneralSettings');

    if ($generalConf->sslPort()) {
        # Enable the SSL module
        try {
            EBox::Sudo::root('a2enmod ssl');
        } catch EBox::Exceptions::Sudo::Command with {
            my ($exc) = @_;
            # Already enabled?
            if ( $exc->exitValue() != 1 ) {
                throw $exc;
            }
        };
        # Overwrite the default-ssl vhost file
        $self->writeConfFile(VHOST_DFLTSSL_FILE, "webserver/default-ssl.mas",
                             [
                                 hostname      => $hostname,
                                 sslportNumber =>  $generalConf->sslPort(),
                                 hostnameVhost  => $hostnameVhost,
                             ],
                            );
        # Enable default-ssl vhost
        try {
            EBox::Sudo::root('a2ensite default-ssl');
        } catch EBox::Exceptions::Sudo::Command with {
            my ($exc) = @_;
            # Already enabled?
            if ( $exc->exitValue() != 1 ) {
                throw $exc;
            }
        };
    } else {
        # Disable the module
        try {
            EBox::Sudo::root('a2dissite default-ssl');
        } catch EBox::Exceptions::Sudo::Command with {
            my ($exc) = @_;
            # Already enabled?
            if ( $exc->exitValue() != 1 ) {
                throw $exc;
            }
        };
        # Disable default-ssl vhost
        try {
            EBox::Sudo::root('a2dismod ssl');
        } catch EBox::Exceptions::Sudo::Command with {
            my ($exc) = @_;
            # Already enabled?
            if ( $exc->exitValue() != 1 ) {
                throw $exc;
            }
        };
    }
}

# Set up the user directory by enable/disable the feature
sub _setUserDir
{
    my ($self) = @_;

    my $generalConf = $self->model('GeneralSettings');
    my $gl = EBox::Global->getInstance();

    # Manage configuration for mod_ldap_userdir apache2 module
    if ( $generalConf->enableDirValue() and $gl->modExists('users') ) {
        my $usersMod = $gl->modInstance('users');
        my $ldap = $usersMod->ldap();
        my $ldapServer = '127.0.0.1';
        my $ldapPort   = $ldap->ldapConf()->{port};
        my $rootDN = $ldap->rootDn();
        my $ldapPass = $ldap->getPassword();
        my $usersDN = EBox::Users::User->defaultContainer()->dn();
        $self->writeConfFile(AVAILABLE_MODS_DIR . LDAP_USERDIR_CONF_FILE,
                             'webserver/ldap_userdir.conf.mas',
                             [
                               ldapServer => $ldapServer,
                               ldapPort  => $ldapPort,
                               rootDN  => $rootDN,
                               usersDN => $usersDN,
                               dnPass  => $ldapPass,
                             ],
                             { 'uid' => 0, 'gid' => 0, mode => '600' }
                            );
        # Enable the modules
        try {
            EBox::Sudo::root('a2enmod ldap_userdir');
        } catch EBox::Exceptions::Sudo::Command with {
            my ($exc) = @_;
            # Already enabled?
            if ( $exc->exitValue() != 1 ) {
                throw $exc;
            }
        };
        try {
            EBox::Sudo::root('a2enmod userdir');
        } catch EBox::Exceptions::Sudo::Command with {
            my ($exc) = @_;
            # Already enabled?
            if ( $exc->exitValue() != 1 ) {
                throw $exc;
            }
        };
    } else {
        # Disable the modules
        try {
            EBox::Sudo::root('a2dismod userdir');
        } catch EBox::Exceptions::Sudo::Command with {
            my ($exc) = @_;
            # Already enabled?
            if ( $exc->exitValue() != 1 ) {
                throw $exc;
            }
        };
        if ( $gl->modExists('users')) {
            try {
                EBox::Sudo::root('a2dismod ldap_userdir');
            } catch EBox::Exceptions::Sudo::Command with {
                my ($exc) = @_;
                # Already disabled?
                if ( $exc->exitValue() != 1 ) {
                    throw $exc;
                }
            };
        }
    }
}

# Set up the virtual hosts
sub _setVHosts
{
    my ($self, $vhosts, $vHostDefault) = @_;

    my $generalConf = $self->model('GeneralSettings');

    # Remove every available site using our vhost pattern ebox-*
    my $vHostPattern = VHOST_PREFIX . '*';
    EBox::Sudo::root('rm -f ' . SITES_ENABLED_DIR . "$vHostPattern");

    my %sitesToRemove = %{_availableSites()};
    if ($vHostDefault) {
        my $vHostDefaultSite = SITES_AVAILABLE_DIR . VHOST_PREFIX . $vHostDefault->{name};
        delete $sitesToRemove{$vHostDefaultSite};
        $self->_createSiteDirs($vHostDefault);
    }

    foreach my $vHost (values %{$vhosts}) {
        my $vHostName  = $vHost->{'name'};
        my $sslSupport = $vHost->{'ssl'};

        my $destFile = SITES_AVAILABLE_DIR . VHOST_PREFIX . $vHostName;
        delete $sitesToRemove{$destFile};
        $self->writeConfFile($destFile,
                             "webserver/vhost.mas",
                             [
                               vHostName => $vHostName,
                               portNumber => $generalConf->portValue(),
                               sslportNumber =>  $generalConf->sslPort(),
                               hostname => $self->_fqdn(),
                               sslSupport => $sslSupport,
                              ],
                            );
        $self->_createSiteDirs($vHost);

        if ( $vHost->{'enabled'} ) {
            my $vhostfile = VHOST_PREFIX . $vHostName;
            try {
                EBox::Sudo::root("a2ensite $vhostfile");
            } catch EBox::Exceptions::Sudo::Command with {
                my ($exc) = @_;
                # Already enabled?
                if ( $exc->exitValue() != 1 ) {
                    throw $exc;
                }
            };
        }

    }

    # Remove not used old dirs
    for my $dir (keys %sitesToRemove) {
        EBox::Sudo::root("rm -f $dir");
    }
}

sub _createSiteDirs
{
    my ($self, $vHost) = @_;
    my $vHostName  = $vHost->{'name'};

    # Create the user-conf subdir if required
    my $userConfDir = SITES_AVAILABLE_DIR . 'user-' . VHOST_PREFIX
        . $vHostName;
    if (EBox::Sudo::fileTest('-e', $userConfDir)) {
        if (not EBox::Sudo::fileTest('-d', $userConfDir)) {
            throw EBox::Exceptions::External(
                  __x('{dir} should be a directory for virtual host configuration. Please, move or remove it',
                      dir => $userConfDir
                     )
            );
        }
    } else {
        EBox::Sudo::root("mkdir -m 755 $userConfDir");
    }

    # Create the directory content if it is not already
    my $dir = EBox::WebServer::PlatformPath::VDocumentRoot()
        . '/' . $vHostName;
    if (EBox::Sudo::fileTest('-e', $dir)) {
        if (not EBox::Sudo::fileTest('-d', $dir)) {
            throw EBox::Exceptions::External(
                  __x('{dir} should be a directory for virtual host document root. Please, move or remove it',
                      dir => $dir
                     )
            );
        }
    } else {
        EBox::Sudo::root("mkdir -p -m 755 $dir");
    }
}

# Return current Zentyal available sites from actual dir
sub _availableSites
{
    my $vhostPrefixPath = SITES_AVAILABLE_DIR . VHOST_PREFIX;
    my @dirs = glob "$vhostPrefixPath*";
    my %dirs = map {$_ => 1} @dirs;
    return \%dirs;
}

# Return fqdn
sub _fqdn
{
    my $fqdn = `hostname --fqdn`;
    if ($? != 0) {
        $fqdn = 'ebox.localdomain';
    }
    chomp $fqdn;
    return $fqdn;
}

# Method: certificates
#
#   This method is used to tell the CA module which certificates
#   and its properties we want to issue for this service module.
#
# Returns:
#
#   An array ref of hashes containing the following:
#
#       service - name of the service using the certificate
#       path    - full path to store this certificate
#       user    - user owner for this certificate file
#       group   - group owner for this certificate file
#       mode    - permission mode for this certificate file
#
sub certificates
{
    my ($self) = @_;

    return [
            {
             serviceId =>  'Web Server',
             service =>  __('Web Server'),
             path    =>  '/etc/apache2/ssl/ssl.pem',
             user => 'root',
             group => 'root',
             mode => '0400',
            },
           ];
}

# Get subjAltNames on the existing certificate
sub _getCertificateSAN
{
    my ($self) = @_;

    my $ca = EBox::Global->modInstance('ca');
    my $certificates = $ca->model('Certificates');
    my $cn = $certificates->cnByService('Web Server');

    my $meta = $ca->getCertificateMetadata(cn => $cn);
    return [] unless $meta;

    my @san = @{$meta->{subjAltNames}};

    my @vhosts;
    foreach my $vhost (@san) {
        push(@vhosts, $vhost->{value}) if ($vhost->{type} eq 'DNS');
    }

    return \@vhosts;
}

# Generate subjAltNames array for zentyal-ca
sub _subjAltNames
{
    my ($self) = @_;

    my $model = $self->model('VHostTable');
    my @subjAltNames;
    foreach my $vhost (@{$model->getWebServerSAN()}) {
        push(@subjAltNames, { type => 'DNS', value => $vhost });
    }

    return \@subjAltNames;
}

# Compare two arrays
sub _checkVhostsLists
{
    my ($self, $vhostsTable, $vhostsCert) = @_;

    my @array1 = @{$vhostsTable};
    my @array2 = @{$vhostsCert};

    my @union = ();
    my @intersection = ();
    my @difference = ();
    my %count = ();

    foreach my $element (@array1, @array2) { $count{$element}++ }
    foreach my $element (keys %count) {
        push(@union, $element);
        push(@{ $count{$element} > 1 ? \@intersection : \@difference }, $element);
    }

    return @difference;
}

# Generate the certificate, issue a new one or renew the existing one
sub _issueCertificate
{
    my ($self) = @_;

    my $ca = EBox::Global->modInstance('ca');
    my $certificates = $ca->model('Certificates');
    my $cn = $certificates->cnByService('Web Server');

    my $caMD = $ca->getCACertificateMetadata();
    my $certMD = $ca->getCertificateMetadata(cn => $cn);

    # If a certificate exists, check if it can still be used
    if (defined($certMD)) {
        my $isStillValid = ($certMD->{state} eq 'V');
        my $isAvailable = (-f $certMD->{path});

        if ($isStillValid and $isAvailable) {
            $ca->renewCertificate(commonName => $cn,
                                  endDate => $caMD->{expiryDate},
                                  subjAltNames => $self->_subjAltNames());
            return;
        }
    }

    $ca->issueCertificate(commonName => $cn,
                          endDate => $caMD->{expiryDate},
                          subjAltNames => $self->_subjAltNames());
}

# Check if we need to regenerate the certificate
sub _checkCertificate
{
    my ($self) = @_;

    my $generalConf = $self->model('GeneralSettings');
    return unless $generalConf->sslPort();

    my $ca = EBox::Global->modInstance('ca');
    my $certificates = $ca->model('Certificates');
    return unless $certificates->isEnabledService('Web Server');

    my $model = $self->model('VHostTable');
    my @vhostsTable = @{$model->getWebServerSAN()};
    my @vhostsCert = @{$self->_getCertificateSAN()};

    return unless @vhostsTable;

    if (@vhostsCert) {
        if ($self->_checkVhostsLists(\@vhostsTable, \@vhostsCert)) {
            $self->_issueCertificate();
        }
    } else {
        $self->_issueCertificate();
    }

    my $global = EBox::Global->getInstance();
    $global->modRestarted('ca');
}

sub dumpConfig
{
    my ($self, $dir) = @_;
    my $sitesBackDir = "$dir/sites-available";
    mkdir $sitesBackDir;

    my @dirs = keys %{ _availableSites() };

    if (not @dirs) {
        EBox::warn(SITES_AVAILABLE_DIR . ' has not custom configuration dirs. Skipping them for the backup');
        return;
    }

    my $toReplace= SITES_AVAILABLE_DIR . 'ebox-';
    my $replacement = SITES_AVAILABLE_DIR . 'user-ebox-';
    foreach my $dir (@dirs) {
       $dir =~ s/$toReplace/$replacement/;
        try {
            EBox::Sudo::root("cp -a $dir $sitesBackDir");
        } catch EBox::Exceptions::Sudo::Command with {
            EBox::error("Failed to do backup of the vhost custom configuration dir $dir");
        };
    }
}

sub restoreConfig
{
    my ($self, $dir) = @_;
    my $sitesBackDir = "$dir/sites-available";
    if (EBox::FileSystem::dirIsEmpty($sitesBackDir)) {
        EBox::warn('No data in the backup for vhosts custom configuration files (maybe the backup was done in a previous version?). Actual files are left untouched');
        return;
    }

    if (not EBox::FileSystem::dirIsEmpty(SITES_AVAILABLE_DIR)) {
        #  backup actual sites-available-dir
        my $backActual = CONF_DIR . '/sites-available.bak';
        $backActual = EBox::FileSystem::unusedFileName($backActual);
        EBox::Sudo::root("mkdir $backActual");
        EBox::Sudo::root('mv ' . SITES_AVAILABLE_DIR .  "/* $backActual");
    }

    EBox::Sudo::root("cp -a $sitesBackDir/* " . SITES_AVAILABLE_DIR);
}

# Implement EBox::SyncFolders::Provider interface
sub syncFolders
{
    my ($self) = @_;

    my @folders;

    if ($self->recoveryEnabled()) {
        foreach my $dir (EBox::WebServer::PlatformPath::DocumentRoot(),
                         EBox::WebServer::PlatformPath::VDocumentRoot()) {
            push (@folders, new EBox::SyncFolders::Folder($dir, 'recovery'));
        }
    }

    return \@folders;
}

sub recoveryDomainName
{
    return __('Web server data');
}

1;
