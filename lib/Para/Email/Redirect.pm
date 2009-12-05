# -*-cperl-*-
package Para::Email::Redirect;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Email Redirect class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use warnings;

use Data::Dumper;
use Carp;

use Para::Frame::Reload;
use Para::Frame::Utils qw( paraframe_dbm_open trim throw debug );
use Para::Frame::Time qw( now );

use Para::Email::Address;
use Para::Domain;
use Para::Member;


sub new
{
    my( $this, $d, $alias, $dest, $in_dbm ) = @_;
    my $class = ref($this) || $this;

    $in_dbm ||= 0;

    my $rec;
    if( ref $dest )
    {
	$rec = $dest;
	$rec->{in_rdb} = 1;
	$rec->{in_dbm} = $in_dbm;
	$rec->{domain} = $d;
    }
    else
    {
	$rec = $Para::dbix->select_possible_record("from mailr where mailr_domain=? and mailr_name=?",$d->id, $alias);

	if( $rec )
	{
	    $rec->{in_rdb} = 1;
	    $rec->{in_dbm} = $in_dbm;
	    $rec->{domain} = $d;
	}
	else
	{
	    $rec =
	    {
		in_rdb => 0,
		in_dbm => 1,
		domain => $d,
		mailr_name => $alias,
		mailr_dest => $dest,
	    };
	}
    }

    return bless $rec, $class;
}

sub create
{
    die "not implemented";

    my( $this, $d, $alias, $email ) = @_;
    my $class = ref($this) || $this;

    my $db = $d->db;
    if( $db->{$alias} )
    {
	die "Alias $alias exist";
    }
    else
    {
	$db->{$alias} = $email;
    }

    return $class->new( $d, $alias, $email );
}

########################################

sub id
{
    return $_[0]->{'mailr'};
}

sub src_raw
{
    return sprintf '%s@%s', $_[0]->alias, $_[0]->domain->name;
}

sub src
{
    return $_[0]->{'src'} ||=
	Para::Email::Address->parse($_[0]->src_raw);
}

sub alias
{
    return $_[0]->{'mailr_name'};
}

sub dest_raw
{
    return $_[0]->{'mailr_dest'};
}

sub dest
{
    return $_[0]->{'dest'} ||=
	Para::Email::Address->parse($_[0]->{'mailr_dest'});
}

sub domain
{
    return $_[0]->{'domain'};
}

sub member
{
    my( $r ) = @_;

    unless( $r->{'member'} )
    {
	my $mid = $r->{'mailr_member'};
	return undef unless defined $mid;
	$r->{'member'} = Para::Member->get_by_id($mid);
    }

    return $r->{'member'};
}

sub created
{
    my( $r ) = @_;

    return undef unless $r->in_rdb;
    return $r->{'created'} ||=
	Para::Frame::Time->get($r->{'mailr_created'});
}

sub in_rdb
{
    return $_[0]->{'in_rdb'};
}

sub in_dbm
{
    return $_[0]->{'in_dbm'};
}

########################################

sub add_in_dbm
{
    my( $r ) = @_;

    my $alias = $r->alias;
    my $dest  = $r->dest;

    my $db = $r->domain->db;

    $db->{ $alias } = $dest;

    $r->{'in_dbm'} = 1;
    return 1;
}

sub add_in_rdb
{
    my( $r ) = @_;

    my $alias = $r->alias;
    my $dest  = $r->dest;

    if( $r->in_rdb )
    {
	return 0; # Already existing
    }

    my $uid = $Para::Frame::U->id;
    my $rid = $Para::dbix->get_nextval('mailr_seq');

    $Para::dbix->insert({
	table => 'mailr',
	rec =>
	{
	    mailr => $rid,
	    mailr_name => $alias,
	    mailr_domain => $r->domain->name,
	    mailr_dest => $dest,
	    mailr_updatedby => $uid,
	},
    });

    my $rec = $Para::dbix->select_record('from mailr where mailr=?',$rid);
    foreach my $key ( keys %$rec )
    {
	$r->{$key} = $rec->{$key};
    }

    $r->{'in_rdb'} = 1;

    $r->domain->{'r_by_id'}{ $rid } = $r;

    return 1;
}

sub set_member
{
    my( $r, $m ) = @_;

    $m or die "m param missing";

    unless( $r->in_rdb )
    {
	throw 'validation', "First sync this record";
    }


    my $u = $Para::Frame::U;

    if( my $m_old = $r->member )
    {
	if( $m_old->equals( $m ) )
	{
	    return $m_old;
	}

	$m_old->del_mailalias( $r->dest );
	$m_old->del_mailalias( $r->src  );
    }

    $r->{'mailr_member'} = $m->id;
    $r->{'member'} = $m;

    $Para::dbix->update('mailr',
			{
			    mailr_member => $m,
			    mailr_updated => now(),
			    mailr_updatedby => $u,
			},
			{
			    mailr => $r,
			});

    $m->add_mailalias( $r->dest );
    $m->add_mailalias( $r->src );

    unless( $m->sys_email )
    {
	$m->set_sys_email( $r->dest );
    }

    my $src = $r->src_raw;
    my $nick = $m->nickname;

    $Para::Frame::REQ->change->success("$src är nu knuten till $nick");
    return;
}

sub set_alias
{
    my( $r, $alias_in ) = @_;

    my $u = $Para::Frame::U;

    my $alias_new = $r->trim_for_alias( $alias_in );
    my $alias_old = $r->alias;

    if( $alias_in ne $alias_new )
    {
	throw 'validation', "Malformed alias $alias_in";
    }


    if( $alias_old eq $alias_new )
    {
	return $alias_old;
    }

    my $src_old = $r->src;

    my $m = $r->member;

    if( $m )
    {
	$m->del_mailalias( $r->src );
    }

    $Para::dbix->update('mailr',
			{
			    mailr_name => $alias_new,
			    mailr_updated => now(),
			    mailr_updatedby => $u,
			},
			{
			    mailr => $r,
			});


    # Remove old data
    my $db = $r->domain->db;
    delete $db->{ $alias_old };
    delete $r->{'src'};
    delete $r->domain->{'r_by_alias'}{ $alias_old };

    # Add new data
    $r->{'mailr_name'} = $alias_new;
    $db->{ $alias_new } = $r->dest_raw;
    $r->domain->{'r_by_alias'}{ $alias_new } = $r;

    if( $m )
    {
	$m->add_mailalias( $r->src );
    }

    my $src_new = $r->src;

    $Para::Frame::REQ->change->success("Ersatte $src_old med $src_new");
    return;
}

sub set_dest
{
    my( $r, $dest_in ) = @_;

    my $u = $Para::Frame::U;

    my $dest_new = Para::Email::Address->parse($dest_in);
    my $dest_old = $r->dest;

    if( $dest_old->equals($dest_new) )
    {
	return $dest_old;
    }

    my $m = $r->member;

    if( $m )
    {
	$m->del_mailalias( $dest_old );
    }

    $Para::dbix->update('mailr',
			{
			    mailr_dest => $dest_new->address,
			    mailr_updated => now(),
			    mailr_updatedby => $u,
			},
			{
			    mailr => $r,
			});

    # Remove old data
    delete $r->{'dest'};

    # Add new data
    $r->{'mailr_dest'} = $dest_new->address;
    my $db = $r->domain->db;
    $db->{ $r->alias } = $dest_new->address;

    if( $m )
    {
	$m->add_mailalias( $r->dest );
	unless( $m->sys_email )
	{
	    $m->set_sys_email( $r->dest );
	}
    }

    $Para::Frame::REQ->change->success("Ersatte $dest_old med $dest_new");
    return;
}

sub trim_for_alias
{
    my( $r, $alias_in ) = @_;

    trim(\$alias_in);
    my $alias = lc($alias_in);
    $alias =~ s/^[^a-z]+//; # alfachar first
    $alias =~ s/[^\w\.\-]//g; # alfanum and dot

    return $alias;
}

sub remove
{
    die "not implemented";

    my( $e ) = @_;

    my $db = $e->domain->db;
    my $alias = $e->alias;
    delete $db->{$alias};
}

1;
