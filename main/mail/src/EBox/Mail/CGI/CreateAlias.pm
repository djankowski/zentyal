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

package EBox::Mail::CGI::CreateAlias;
use base 'EBox::CGI::ClientPopupBase';

use EBox::Global;
use EBox::Mail;
use EBox::Gettext;
use EBox::Exceptions::External;

sub new
{
        my $class = shift;
        my $self = $class->SUPER::new('title' => 'Mail',
                                      @_);
        bless($self, $class);
        return $self;
}

sub _process
{
    my ($self) = @_;

    $self->{json}->{success} = 0;
    my $mail = EBox::Global->modInstance('mail');

    $self->_requireParam('user', __('user'));
    my $userDN = $self->unsafeParam('user');
    $self->{json}->{userDN} = $userDN;

    $self->_requireParam('maildrop', __('maildrop'));
    $self->_requireParam('lhs', __('account name'));
    $self->_requireParam('rhs', __('domain name'));

    my $maildrop = $self->param('maildrop');
    my $lhs = $self->param('lhs');
    my $rhs = $self->param('rhs');

    $mail->{malias}->addAlias($lhs."@".$rhs, $maildrop, $maildrop);
    $self->{json}->{success} = 1;
}

1;
