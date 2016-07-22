# -*-cperl-*-
package Para::Mailbox;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Mailbox class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Mailbox - Representing local member mailbox

=cut

use strict;
use warnings;

use vars qw( $VERSION );
use Carp qw( croak );

use IMAP::Admin;
use Data::Dumper;

use Para::Frame::Reload;

use Para::Frame::Utils qw( debug throw );


sub new
{
	my( $class, $m ) = @_;

	my $mbx =
	{
	 member => $m,
	};

	bless $mbx, $class;
	$mbx->imap_connect;

	return $mbx;
}

sub imap_connect
{
	my( $mbx ) = @_;

	my $imap = IMAP::Admin->new(
															'Server' => 'localhost',
															'Login' => 'cyrus',
															'Password' => 'tingeling',
														 )
		or die "Failed to connect to IMAP server\n";

	$mbx->{'imap'} = $imap;
}

sub member
{
	my( $mbx ) = @_;
	return $mbx->{'member'};
}

sub imap
{
	my( $mbx ) = @_;
	return $mbx->{'imap'};
}

sub root
{
	my( $mbx ) = @_;

	my $sys_uid = $mbx->member->sys_uid;
	return '' unless $sys_uid;
	return "user.$sys_uid";
}

sub exist
{
	my( $mbx, $folder ) = @_;

	my $root = $mbx->root;
	return 0 unless $root;

	$folder ||= $root;
	unless( $folder =~ /^$root/ )
	{
		throw('validate', "Folder $folder does not belong to member");
	}

	debug "Checking for $folder";
	return $mbx->imap->list( $folder ) ? 1 : 0;
}

sub quota
{
	my( $mbx, $new ) = @_;

	my $mbx_root = $mbx->root;
	my( $name, $used, $quota ) = $mbx->imap->get_quota( $mbx_root );

	if ( $new and $new != $quota )
	{
		$quota = $new;
		my $err = $mbx->imap->set_quota( $mbx_root, $quota );
		if ( $err )
		{
	    die "Could not change quota for $mbx_root: ".$mbx->imap->{'Error'}."\n";
		}
	}

	return $quota;
}

sub used
{
	my( $mbx ) = @_;

	my( $name, $used, $quota ) = $mbx->imap->get_quota( $mbx->root );

	return $used;
}

sub create
{
	my( $mbx ) = @_;

	my $imap = $mbx->imap;
	my $root = $mbx->root;

	return 1 if $mbx->exist;

	$imap->create($root) and die "Failed to create mailbox $root: ".$imap->{'Error'};
	$imap->set_quota($root, 10000); # 10 MB
	$imap->set_acl($root, 'cyrus', 'lrswipcda');

	$mbx->create_folder("Sent");
	$mbx->create_folder("Trash");

	return 1;
}

sub create_folder
{
	my( $mbx, $folder ) = @_;

	my $imap = $mbx->imap;
	my $root = $mbx->root;

	unless( $folder =~ /^$root/ )
	{
		$folder = $root . '.' . $folder;
	}

	return 1 if $mbx->exist($folder);

	$imap->create($folder) and die $imap->{'Error'};
	$imap->set_acl($folder, 'cyrus', 'lrswipcda');

	return $folder;
}

sub list
{
	my( $mbx ) = @_;

	my $imap = $mbx->imap;
	my $root = $mbx->root;

	return undef unless $mbx->exist;

	my @folders = ();
	foreach my $folder ( $imap->list("$root.*") )
	{
		push @folders, $folder;
#	warn "-> $folder\n";
	}
	return \@folders;
}

sub remove
{
	my( $mbx, $extra ) = @_;

	croak "too many args" if defined $extra;

	my $imap = $mbx->imap;
	my $root = $mbx->root;

	return 1 unless $root;				#Doesn't exist to begin with
	return 1 unless $mbx->exist;

	# Caution check
	my $quota = $mbx->quota;
	if ( $quota < 1 )
	{
		throw('validation', "The quota for mailbox seems wrong");
	}
	elsif ( $quota > 20000 )
	{
		throw('validation', "I will not remove somebody with quota over 20000");
	}

	# remove subfolders deatch first
	#
	my $folders = $mbx->list;
	foreach my $folder ( sort { length( $b ) <=> length( $a ) } @$folders )
	{
		$mbx->remove_folder( $folder );
	}

	$imap->delete($root) and die "Failed to remove mailbox $root: $imap->{'Error'}\n";

	my $m = $mbx->member;
	$m->unset_dbm_passwd;
	$m->unset_sys_uid;
	$m->update_mail_forward;

	return 1;
}

sub remove_folder
{
	my( $mbx, $folder ) = @_;

	$folder or die "no folder given";

	my $imap = $mbx->imap;
	my $root = $mbx->root;

	unless( $folder =~ /^$root/ )
	{
		$folder = $root . '.' . $folder;
	}

	return 1 unless $mbx->exist($folder);

	# Give acces to delete if not yet given
	$imap->set_acl($folder, 'cyrus', 'lrswipcda');
	$imap->delete($folder) and die "Failed to remove mailbox $root: $imap->{'Error'}\n";

	return 1;
}


1;
