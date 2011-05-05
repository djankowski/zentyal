# Copyright (C) 2008-2011 eBox Technologies S.L.
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

# Class: EBox::Services
#
#       This class is used to abstract services composed of
#       protocols and ports.
#

package EBox::Services;

use strict;
use warnings;

use base qw(EBox::GConfModule EBox::Model::ModelProvider);

use EBox::Validate qw( :all );
use EBox::Global;
use EBox::Services::Model::ServiceConfigurationTable;
use EBox::Services::Model::ServiceTable;
use EBox::Gettext;

use EBox::Exceptions::InvalidData;
use EBox::Exceptions::MissingArgument;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataMissing;
use EBox::Exceptions::DataNotFound;

use Error qw(:try);

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'services',
                                      printableName => __('Services'),
                                      @_);
    bless($self, $class);

    $self->{'serviceModel'} = $self->model('ServiceTable');
    $self->{'serviceConfigurationModel'} = $self->model('ServiceConfigurationTable');

    return $self;
}

# Method: initialSetup
#
# Overrides:
#   EBox::Module::Base::initialSetup
#
sub initialSetup
{
    my ($self, $version) = @_;

    foreach my $service (@{$self->_defaultServices()}) {
        $service->{'sourcePort'} = 'any';
        $service->{'readOnly'} = 1;
        if ($self->serviceExists('name' => $service->{'name'})) {
            $self->setService(%{$service});
        } else {
            $self->addService(%{$service});
        }
    }
}

sub _defaultServices
{
    my ($self) = @_;

    my $apachePort;
    try {
        $apachePort = EBox::Global->modInstance('apache')->port();
    } otherwise {
        $apachePort = 443;
    };

    return [
        {
         'name' => 'any',
         'description' => __d('any protocol and port'),
         'protocol' => 'any',
         'destinationPort' => 'any',
         'internal' => 0,
        },
        {
         'name' => 'any UDP',
         'description' => __d('any UDP port'),
         'protocol' => 'udp',
         'destinationPort' => 'any',
         'internal' => 0,
        },
        {
         'name' => 'any TCP',
         'description' => __d('any TCP port'),
         'protocol' => 'tcp',
         'destinationPort' => 'any',
         'internal' => 0,
        },
        {
         'name' => 'eBox administration',
         'description' => __d('Zentyal Administration Web Server'),
         'protocol' => 'tcp',
         'destinationPort' => $apachePort,
         'internal' => 1,
        },
        {
         'name' => 'ssh',
         'description' => 'SSH',
         'protocol' => 'tcp',
         'destinationPort' => '22',
         'internal' => 0,
        },
        {
         'name' => 'HTTP',
         'description' => 'HTTP',
         'protocol' => 'tcp',
         'destinationPort' => '80',
         'internal' => 0,
        },
    ];
}

# Method: modelClasses
#
# Overrides:
#
#      <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{
    # TODO: Remove customized directory names and rename them
    # in the migration script from Zentyal 2.0 to 2.2 ?
    return [
        {
          class => 'EBox::Services::Model::ServiceTable',
          parameters => [ directory => 'serviceTable' ],
        },
        {
          class => 'EBox::Services::Model::ServiceConfigurationTable',
          parameters => [ directory => 'serviceConfigurationTable' ],
        },
    ];
}

# Method: exposedMethods
#
# Overrides:
#
#      <EBox::Model::ModelProvider::_exposedMethods>
#
# Returns:
#
#      hash ref - the list of the exposes method in a hash ref every
#      component
#
sub _exposedMethods
{
    my %exposedMethods =
       (
        'serviceName'     => { action   => 'get',
                               path     => [ 'ServiceTable' ],
                               indexes  => [ 'id' ],
                               selector => [ 'name' ],
                             },
        'serviceId'       => { action   => 'get',
                               path     => [ 'ServiceTable' ],
                               indexes  => [ 'name' ],
                               selector => [ 'id' ],
                             },
        'service'         => { action   => 'get',
                               path     => [ 'ServiceTable' ],
                               indexes  => [ 'id' ],
                             },
         'updateDestPort' => { action   => 'set',
                               path     => [ 'ServiceTable', 'configuration' ],
                               indexes  => [ 'name', 'id' ],
                               selector => [ 'destination' ],
                             },
         'addSrvConf'     => { action   => 'add',
                               path     => [ 'ServiceTable', 'configuration' ],
                               indexes  => [ 'name' ],
                             },
         'delSrvConf'     => { action   => 'del',
                               path     => [ 'ServiceTable', 'configuration' ],
                               indexes  => [ 'name', 'id' ],
                             },
         'srvConf'        => { action   => 'get',
                               path     => [ 'ServiceTable' ],
                               indexes  => [ 'name' ],
                             },
       );

    return \%exposedMethods;
}

# Method: serviceNames
#
#       Fetch all the service identifiers and names
#
# Returns:
#
#       Array ref of  hash refs which contain:
#
#       'id' - service identifier
#       'name' service name
#
#       Example:
#         [
#          {
#            'name' => 'ssh',
#            'id' => 'serv7999'
#          },
#          {
#            'name' => 'ftp',
#            'id' => 'serv7867'
#          }
#        ];
sub serviceNames
{
    my ($self) = @_;

    my $servicesModel = $self->{'serviceModel'};
    my @services;

    foreach my $id (@{$servicesModel->ids()}) {
        my $name = $servicesModel->row($id)->valueByName('name');
        push @services, {
            'id' => $id,
            'name' => $name
           };
    }

    return \@services;
}

# Method: serviceConfiguration
#
#       For a given service identifier it returns its service configuration,
#       that is, the set of protocols and ports.
#
# Returns:
#
#       Array ref of  hash refs which contain:
#
#       protocol - it can take one of these: any, tcp, udp, tcp/udp, grep, icmp
#       source   - it can take:
#                       "any"
#                       An integer from 1 to 65536 -> 22
#                       Two integers separated by colons -> 22:25
#       destination - same as source
#
#       Example:
#         [
#             {
#              'protocol' => 'tcp',
#               'source' => 'any',
#               'destination' => '21:22',
#             }
#         ]
sub serviceConfiguration
{
    my ($self, $id) = @_;

    throw EBox::Exceptions::ArgumentMissing("id") unless defined($id);

    my $row = $self->{'serviceModel'}->row($id);

    unless (defined($row)) {
        throw EBox::Exceptions::DataNotFound('data' => 'id',
                'value' => $id);
    }

    my $model = $row->subModel('configuration');

    my @conf;
    for my $id (@{$model->ids()}) {
	my $subRow = $model->row($id);
        push (@conf, {
                        'protocol' => $subRow->valueByName('protocol'),
                        'source' => $subRow->valueByName('source'),
                        'destination' => $subRow->valueByName('destination')
                      });
    }

    return \@conf;
}

# Method: addService
#
#   Add a service to the services table
#
# Parameters:
#
#   (NAMED)
#
#   name        - service's name
#   description - service's description
#   protocol    - it can take one of these: any, tcp, udp, tcp/udp, grep, icmp
#   sourcePort  - it can take:
#                   "any"
#                   An integer from 1 to 65536 -> 22
#                   Two integers separated by colons -> 22:25
#   destinationPort - same as source
#   internal - boolean, internal services can't be modified from the UI
#   readOnly - boolean, set the row unremovable from the UI
#
#       Example:
#
#       'name' => 'ssh',
#       'description' => 'secure shell'.
#           'protocol' => 'tcp',
#           'sourcePort' => 'any',
#       'destinationPort' => '21:22',
#
#   Returns:
#
#   string - id of the new created row
sub addService
{
    my ($self, %params) = @_;

    return $self->{'serviceModel'}->addService(%params);
}

# Method: addMultipleService
#
#   Add a multi protocol service to the services table
#
# Parameters:
#
#   (NAMED)
#
#   name        - service's name
#   description - service's description
#   internal - boolean, internal services can't be modified from the UI
#   readOnly - boolean, set the row unremovable from the UI
#
#   services - array ref of hash ref containing:
#
#           protocol    - it can take one of these: any, tcp, udp,
#                                                   tcp/udp, grep, icmp
#           sourcePort  - it can take:  "any"
#                                   An integer from 1 to 65536 -> 22
#                                   Two integers separated by colons -> 22:25
#           destinationPort - same as source
#
#
#       Example:
#
#       'name' => 'ssh',
#       'description' => 'secure shell'.
#       'services' => [
#                       {
#                               'protocol' => 'tcp',
#                               'sourcePort' => 'any',
#                           'destinationPort' => '21:22'
#                        },
#                        {
#                               'protocol' => 'tcp',
#                               'sourcePort' => 'any',
#                           'destinationPort' => '21:22'
#                        }
#                     ];
#
#   Returns:
#
#   string - id of the new created row
sub addMultipleService
{
    my ($self, %params) = @_;

    return $self->{'serviceModel'}->addMultipleService(%params);
}

# Method: setService
#
#   Set a existing service to the services table
#
# Parameters:
#
#   (NAMED)
#
#   name        - service's name
#   description - service's description
#       protocol    - it can take one of these: any, tcp, udp, tcp/udp, grep, icmp
#       sourcePort  - it can take:
#                   "any"
#                    An integer from 1 to 65536 -> 22
#                   Two integers separated by colons -> 22:25
#       destinationPort - same as source
#   internal - boolean, internal services can't be modified from the UI
#   readOnly - boolean, set the row unremovable from the UI
#
#       Example:
#
#       'name' => 'ssh',
#       'description' => 'secure shell'.
#           'protocol' => 'tcp',
#           'sourcePort' => 'any',
#       'destinationPort' => '21:22',
sub setService
{
    my ($self, %params) = @_;

    $self->{'serviceModel'}->setService(%params);
}

# Method: setMultipleService
#
#   Set a multi protocol service to the services table
#
# Parameters:
#
#   (NAMED)
#
#   name        - service's name
#   description - service's description
#   internal - boolean, internal services can't be modified from the UI
#   readOnly - boolean, set the row unremovable from the UI
#
#   services - array ref of hash ref containing:
#
#	    protocol    - it can take one of these: any, tcp, udp,
#	                                            tcp/udp, grep, icmp
#	    sourcePort  - it can take:  "any"
#                                   An integer from 1 to 65536 -> 22
#                                   Two integers separated by colons -> 22:25
#	    destinationPort - same as source
#
#
#	Example:
#
#       'name' => 'ssh',
#       'description' => 'secure shell'.
#       'services' => [
#                       {
#	                        'protocol' => 'tcp',
#	                        'sourcePort' => 'any',
#                               'destinationPort' => '21:22'
#                        },
#                        {
#	                        'protocol' => 'tcp',
#	                        'sourcePort' => 'any',
#                               'destinationPort' => '21:22'
#                        }
#                     ];
#
#   Returns:
#
#   string - id of the updated row
#
sub setMultipleService
{
    my ($self, %params) = @_;

    $self->{'serviceModel'}->setMultipleService(%params);
}

# Method: setAdministrationPort
#
#       Set administration port on service
#
# Parameters:
#
#       port - port
#
sub setAdministrationPort
{
    my ($self, $port) = @_;

    checkPort($port, __("port"));

    $self->setService('name' => __d('eBox administration'),
            'description' => __d('Zentyal Administration Web Server'),
            'protocol' => 'tcp',
            'sourcePort' => 'any',
            'destinationPort' => $port,
            'internal' => 1,
            'readOnly' => 1);
}

# Method: availablePort
#
#       Check if a given port for a given protocol is available. That is,
#       no internal service uses it.
#
# Parameters:
#
#   (POSITIONAL)
#   protocol   - it can take one of these: tcp, udp
#   port           - An integer from 1 to 65536 -> 22
#
# Returns:
#   boolean - true if it's available, otherwise false
#
sub availablePort
{
    my ($self, %params) = @_;

    return $self->{'serviceModel'}->availablePort(%params);
}

# Method: serviceFromPort
#
#       Get the service name that it's using a port.
#
# Parameters:
#
#   (POSITIONAL)
#   protocol   - it can take one of these: tcp, udp
#   port       - An integer from 1 to 65536 -> 22
#
# Returns:
#   string - the service name, undef otherwise
#
sub serviceFromPort
{
    my ($self, %params) = @_;

    return $self->{'serviceModel'}->serviceFromPort(%params);
}

# Method: removeService
#
#  Remove a service from the  services table
#
# Parameters:
#
#   (NAMED)
#
#   You can select the service using one of the following parameters:
#
#       name - service's name
#       id - service's id
sub removeService
{
    my ($self, %params) = @_;

    unless (exists $params{'id'} or exists $params{'name'}) {
        throw EBox::Exceptions::MissingArgument('service');
    }

    my $model =  $self->{'serviceModel'};
    my $id = $params{'id'};

    if (not defined($id)) {
        my $name = $params{'name'};
        my $row = $model->findValue('name' => $name);
        unless (defined($row)) {
            throw EBox::Exceptions::External("service $name not found");
        }
        $id = $row->id();
    }

    $model->removeRow($id, 1);
}

# Method: serviceExists
#
#   Check if a given service already exits
#
# Paremeters:
#
#   (NAMED)
#   You can select the service using one of the following parameters:
#
#       name - service's name
#       id - service's id
sub serviceExists
{
    my ($self, %params) = @_;

    unless (exists $params{'id'} or exists $params{'name'}) {
        throw EBox::Exceptions::MissingArgument('service id or name');
    }

    my $model =  $self->{'serviceModel'};
    my $id = $params{'id'};

    my $row;
    if (not defined($id)) {
        my $name = $params{'name'};
        $row = $model->findValue('name' => $name);
    } else {
        $row = $model->row($id);
    }

    return defined($row);
}

# Method: serviceId
#
#   Given a service's name it returns its id
#
# Paremeters:
#
#   (POSITIONAL)
#
#   name - service's name
#
# Returns:
#
#   service's id if it exists, otherwise undef
sub serviceId
{
    my ($self, $name) = @_;

    unless (defined($name)) {
        throw EBox::Exceptions::MissingArgument('name');
    }

    my $model = $self->{'serviceModel'};
    my $row = $model->findValue('name' => $name);
    if (not defined $row) {
        return undef;
    }

    return $row->id();
}

# Method: menu
#
#       Overrides EBox::Module method.
#
#
sub menu
{
    my ($self, $root) = @_;
    my $item = new EBox::Menu::Item(
    'url' => 'Services/View/ServiceTable',
    'text' => __($self->title),
    'separator' => 'Core',
    'order' => 60);
    $root->add($item);
}

1;