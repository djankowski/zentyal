#!/usr/bin/perl
# Copyright (C) 2011 eBox Technologies S.L.
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

# Import DNS Server configuration from a YAML file

use warnings;
use strict;

use EBox;
use EBox::Global;
use Error qw(:try);
use YAML::XS;

if (@ARGV ne 1) {
    print "Exported DNS servers info expected. Usage:\n";
    print "$0 exported_file.txt\n";
    exit 1;
}

EBox::init();

if (not EBox::Global->modExists('dns')) {
    print "DNS module is not installed. Aborting\n";
    exit 1;
}

# Import configuration file
my ($dns_zones) = YAML::XS::LoadFile($ARGV[0]);

my $network = EBox::Global->modInstance('network');
my $dns = EBox::Global->modInstance('dns');
my $manager = EBox::Model::ModelManager->instance();

foreach my $zone (@$dns_zones) {

    my @hostnames;
    if ($zone->{records}) {
        foreach my $record (@{$zone->{records}}) {
            if ($record->{type} eq 'A') {
                push (@hostnames,
                        {
                        'hostname' => $record->{name},
                        'ip'       => $record->{ip},
                        'aliases'  => [],

                        }
                     );
            }
        }
    }

    $dns->addDomain({domain_name => $zone->{name}, hostnames => \@hostnames});
}
