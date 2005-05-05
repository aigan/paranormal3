#  $Id$  -*-perl-*-
package Para::Alias;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se topic aliases
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Data::Dumper;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( minof throw );
use Para::Frame::Time;

use Para::Topic qw( title2url );
use Para::Constants qw( :all );
use Para::History;

use Carp;
use vars qw( $DEBUG );
use locale;

$DEBUG = 0;

sub new
{
    # Get relation(s) matching the params
    #
    my( $this, $rec ) = @_;
    my $class = ref($this) || $this;

    unless( ref $rec eq 'HASH' )
    {
	die "Not implemented";
    }

    return bless( $rec, $class );
}

sub list
{
    my( $class, $t, $args ) = @_;

    return undef unless ref $t;
    $args ||= {};

    my $extra = "";
    if( $args->{'include_inactive'} )
    {
	warn "Include inactive aliases in list\n" if $DEBUG;
    }
    else
    {
	$extra .= " and talias_active is true";
	warn "Will not include inactive aliases in list\n" if $DEBUG;
    }

    my $list = $Para::dbix->select_list("from talias where talias_t=? $extra", $t->id);

    my @aliases;
    foreach my $rec ( @$list )
    {
	push @aliases, Para::Alias->new( $rec );
    }
    return \@aliases;
}

sub add
{
    my( $this, $t, $alias_name, $props ) = @_;
    my $class = ref($this) || $this;

    $alias_name = lc( $alias_name );

    warn "Adding alias $alias_name\n" if $DEBUG;

    if( my $a = $class->get( $t, $alias_name ) )
    {
	warn "  Already exists. Updating\n" if $DEBUG;
	return $a->update( $props );
    }

    my $m = $Para::u;
    my $st_alias_add =
      "insert into talias ( talias_t, talias, talias_urlpart,
                            talias_createdby, talias_changedby,
                            talias_status, talias_autolink,
                            talias_index, talias_language,
                            talias_active )
              values ( ?, lower(?), ?, ?, ?, ?, ?, ?, ?, ? )";
    my $sth_alias_add = $Para::dbh->prepare_cached( $st_alias_add );

    my $talias_t         = $t->id or die;
    my $talias           = $alias_name or die;
    die "wrong indata" if ref $talias;
    my $talias_urlpart   = title2url($talias);
    my $talias_createdby = $m->id;
    my $talias_changedby = $m->id;
    my $talias_status    = minof( $m->new_status, $props->{'status'});
    my $talias_autolink  = defined $props->{'autolink'} ? $props->{'autolink'} : 1;
    my $talias_index     = defined $props->{'index'} ? $props->{'index'} : 1;
    my $talias_language  = $props->{'language'} || undef;
    $talias_language = $talias_language->id if ref $talias_language;
    $talias_language = undef unless $talias_language;
    my $talias_active = $talias_status >= S_PENDING ? 1 : 0;

    $sth_alias_add->execute( $talias_t, $talias, $talias_urlpart,
			     $talias_createdby, $talias_changedby,
			     $talias_status, pgbool($talias_autolink),
			     pgbool($talias_index), $talias_language,
			     pgbool($talias_active) );

    Para::History->add('talias', HA_CREATE,
		      {
			  topic => $t,
			  skey  => $alias_name,
		      });

    $t->mark_publish;

    # TODO: Skip this step
    return $class->get( $t, $alias_name );
}

sub get
{
    my( $class, $t, $alias_name, $props ) = @_;

    confess $alias_name unless length $alias_name;
    warn "get alias $alias_name\n" if $DEBUG;

    confess "invalid input: $t" unless ref $t;
    confess 'not implemented' if $props;
    my $rec = $Para::dbix->select_possible_record("from talias where talias_t=? and talias=?",
				     $t->id, $alias_name);
    if( $rec )
    {
	return $class->new( $rec );
    }
    else
    {
	warn "  not found\n" if $DEBUG;
	return undef;
    }
}


sub name   { shift->{'talias'} }
sub alias  { shift->{'talias'} }
sub desig  { shift->{'talias'} }
sub status { shift->{'talias_status'} }
sub active { shift->{'talias_active'} }
sub autolink { shift->{'talias_autolink'} }
sub index  { shift->{'talias_index'} }

sub language
{
    my( $a ) = @_;
    return undef unless $a->{'talias_language'};
    return Para::Topic->new( $a->{'talias_language'} );
}

sub language_id
{
    my( $a ) = @_;
    return undef unless $a->{'talias_language'};
    return $a->{'talias_language'};
}

sub topic
{
    my( $a ) = @_;
    return Para::Topic->new( $a->{'talias_t'} );
}

sub created_by
{
    Para::Member->get( shift->{'talias_createdby'} || -1 );
}

sub updated_by
{
    Para::Member->get( shift->{'talias_changedby'} || -1 );
}

sub created
{
    return Para::Time->get( shift->{'talias_created'} );
}

sub updated
{
    return Para::Time->get( shift->{'talias_updated'} );
}

sub activate
{
    my( $a ) = @_;

    my $m = $Para::u;

    $a->update({
		status => $m->new_status,
	       });
    return $a;
}

sub update
{
    my( $a, $props ) = @_;

    my $m = $Para::u;

    # The props hash:
    #
    # active    : true / false
    # status    : numerical
    # language  : undef / tid / topic
    # index     : true / false
    # autolink  : true / false
    # quiet     : true / false ( ignore authorization error )

    if( $props->{'status'} and $props->{'status'} > $m->status )
    {
        throw 'denied', "Du kan inte ge aliaset en så hög status\n";
    }

    # Convert language to tid / undef
    #
    if( $props->{'language'} )
    {
	if( ref $props->{'language'} )
	{
	    $props->{'language'} = $props->{'language'}->id;
	}
    }
    else
    {
	$props->{'language'} = undef;
    }

    warn sprintf("  updating alias %s\n", $a->desig) if $DEBUG;

    warn "  Got ".Dumper($props) if $DEBUG;


    # Check to see if anything changed
    #
    my $changed = 0;
    if( defined $props->{'autolink'} and ($props->{'autolink'} xor $a->autolink) )
    {
	if( $DEBUG )
	{
	    warn sprintf( "  Autolink changed; %d -> %d\n",
			  $a->autolink, $props->{'autolink'} );
	}
	Para::History->add('talias', HA_UPDATE,
			  {
			      topic => $a->topic,
			      skey  => $a->name,
			      slot  => 'autolink',
			      vold  => $a->autolink,
			      vnew  => $props->{'autolink'},
			  });
	$changed++;
    }
    if( defined $props->{'index'} and ($props->{'index'} xor $a->index ) )
    {
	if( $DEBUG )
	{
	    warn sprintf( "  Index changed: %d -> %d\n",
			  $a->index, $props->{'index'} );
	}
	Para::History->add('talias', HA_UPDATE,
			  {
			      topic => $a->topic,
			      skey  => $a->name,
			      slot  => 'index',
			      vold  => $a->index,
			      vnew  => $props->{'index'},
			  });
	$changed++;
    }
    if( defined $props->{'language'} and (($props->{'language'}||0) != ($a->language_id||0)) )
    {
	if( $DEBUG )
	{
	    warn sprintf( "  Language changed: %s -> %s\n",
			  ( $a->language ? $a->language->desig : '<none>' ),
			  ( $props->{'language'} ?
			    Para::Topic->new( $props->{'language'} )->desig :
			    '<none>' ),
			);
	}
	Para::History->add('talias', HA_UPDATE,
			  {
			      topic => $a->topic,
			      skey  => $a->name,
			      slot  => 'language',
			      vold  => $a->language_id,
			      vnew  => $props->{'language'},
			  });
	$changed++;
    }


    # The variables that can be changed
    #
    my $changedby = $m->id;
    my $autolink  = pgbool( exists $props->{'autolink'} ? $props->{'autolink'} : $a->autolink );
    my $index     = pgbool( exists $props->{'index'} ? $props->{'index'} : $a->index );
    my $language = exists $props->{'language'} ? $props->{'language'} : $a->language_id;


    # The status of the alias
    #
    my( $active, $status );
    if( defined $props->{'status'} )
    {
	$status = $props->{'status'};
	$active = $props->{'status'} >= S_PENDING ? 1 : 0;

	# Status changed explicitly?
	#
	if( $status != $a->status )
	{
	    if( $DEBUG )
	    {
		warn sprintf( "  Status changed: %d -> %d\n",
			      $a->status, $status );
	    }
	    Para::History->add('talias', HA_UPDATE,
			      {
				  topic => $a->topic,
				  skey  => $a->name,
				  slot  => 'status',
				  vold  => $a->status,
				  vnew  => $status,
			      });
	    $changed ++;
	}
    }
    elsif( defined $props->{'active'} )
    {
	$active = $props->{'active'};
	if( $a->status >= S_PENDING )
	{
	    if( not $active )
	    {
		$status = S_DENIED;
		$changed ++;
		warn "  Status changed to DENIED\n" if $DEBUG;
	    }
	}
	else
	{
	    if( $active )
	    {
		$status = $m->new_status;
		Para::History->add('talias', HA_UPDATE,
				  {
				      topic => $a->topic,
				      skey  => $a->name,
				      slot  => 'status',
				      vold  => $a->status,
				      vnew  => $status,
				  });
		$changed ++;
		warn "  Alias deactivated\n" if $DEBUG;
	    }
	}
    }

    # Return unless any changes requested
    #
    if( $changed )
    {
	warn "  Changes detected. Store update\n" if $DEBUG;
    }
    else
    {
	warn "  No changes\n" if $DEBUG;
	return $a;
    }

    # Check authorization
    #
    if( $a->status > $m->status )
    {
	if( $props->{'quiet'} )
	{
	    warn "  Status to low. But be quiet about it\n" if $DEBUG;
	    return $a;
	}
	else
	{
	    throw 'denied',
	      sprintf( "Du har för låg nivå för att ändra aliaset %s\n",
		       $a->desig );
	}
    }

    my $talias_t = $a->topic->id;
    my $talias = $a->alias;
    $active = $a->active unless defined $active;
    $status = $a->status unless defined $status;
    $active = pgbool( $active );


    if( $status > $a->status )
    {
	$m->score_change( 'accepted_thing' );
	$a->created_by->score_change( 'thing_accepted' );
    }
    if( $a->active and $active eq 'f' )
    {
	$m->score_change( 'rejected_thing' );
	$a->created_by->score_change( 'thing_rejected' );
    }

    my $st = "update talias set talias_autolink=?,
                                talias_index=?,
                                talias_language=?,
                                talias_status=?,
                                talias_active=?,
                                talias_changedby=?,
                                talias_updated=now()
                            where talias_t=? and talias=?";
    my $sth = $Para::dbh->prepare_cached( $st );

    $sth->execute( $autolink, $index, $language, $status,
		   $active, $changedby, $talias_t, $talias );

    warn "  updated (S$status)!\n" if $DEBUG;

    $a->topic->mark_publish;

    $a->reset;
    return $a;
}

sub remove
{
    die 'not implemented';
}

sub reset
{
    my( $a ) = @_;

    my $rec = $Para::dbix->select_record("from talias where talias_t=? and talias=?",
			    $a->topic->id, $a->name);
    foreach my $key ( keys %$rec )
    {
	$a->{$key} = $rec->{$key};
    }

    return $a;
}

sub vacuum
{
    my( $a ) = @_;

}

1;
