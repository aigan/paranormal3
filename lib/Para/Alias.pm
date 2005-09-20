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
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( minof throw debug trim reset_hashref );
use Para::Frame::DBIx qw( pgbool );
use Para::Frame::Time qw( date );

use Para::Topic qw( title2url );
use Para::Constants qw( :all );
use Para::History;

use Carp;
use locale;

sub _new
{
    # Create object from record
    #
    # OBS! Get the object from cache if existing, before using this

    my( $this, $rec ) = @_;
    my $class = ref($this) || $this;

    unless( ref $rec eq 'HASH' )
    {
	die "Not implemented";
    }

    return bless( $rec, $class );
}

=head2 find_by_name

    $class->find_by_name( $name );
    $class->find_by_name( $name, \%crits );

crits:
  active
  status_min

returns arrayref of aliases

=cut

sub find_by_name
{
    my( $class, $name, $crits ) = @_;

    $name = trim lc $name;

    debug(3,"Finding alias by name $name",1);

    unless( $Para::Alias::CACHE{$name} )
    {
	my $list = $Para::dbix->select_list("select talias_t, talias
                                from talias where talias=?", $name);
	$Para::Alias::CACHE{$name} = [];
	debug(4,"Initiating alias name cache");
	foreach my $rec ( @$list )
	{
	    my $tid = $rec->{'talias_t'};

	    my $a = $class->find_by_tid( $tid )->{$name};

	    push @{$Para::Alias::CACHE{$name}}, $a;
	}
    }

    debug(-1);

    if( $crits )
    {
	my @res = ();

	my $crit_active = $crits->{'active'};
	my $crit_status_min = $crits->{'status_min'} || 0;

	foreach my $a ( @{$Para::Alias::CACHE{$name}} )
	{
	    debug(4,"  checking ".$a->desig);

	    if( $crit_active )
	    {
		next unless $a->active;
	    }

	    next unless $a->status >= $crit_status_min;

	    debug(4,"    passed");
	    push @res, $a;
	}
	return \@res;
    }

    return $Para::Alias::CACHE{$name};
}

=head2 find_by_tid

    $class->fins_by_tid( $tid );

returns hashref with alias => object pairs

=cut

sub find_by_tid
{
    my( $class, $tid ) = @_;

    debug(3,"Finding alias by tid $tid");

    unless( $Para::Topic::ALIASES{$tid} )
    {
	debug(4,"  Initiating topic aliases cache");
	$Para::Topic::ALIASES{$tid} = {};

	my $list = $Para::dbix->select_list("from talias where talias_t=?", $tid);
	foreach my $rec ( @$list )
	{
	    my $a = $class->_new( $rec );
	    debug(5,"    Adding $a->{talias}");
	    $Para::Topic::ALIASES{$tid}{ $a->name } = $a;
	}
    }

    return $Para::Topic::ALIASES{$tid};
}

### Accessors

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
    return Para::Topic->get_by_id( $a->{'talias_language'} );
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
    return Para::Topic->get_by_id( $a->{'talias_t'} );
}

sub t
{
    return Para::Topic->get_by_id( $_[0]->{'talias_t'} );
}

sub tid
{
    return $_[0]->{'talias_t'};
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
    unless( ref $_[0]->{'talias_created'} )
    {
	$_[0]->{'talias_created'} = date( $_[0]->{'talias_created'} );
    }
    return $_[0]->{'talias_created'};
}

sub updated
{
    unless( ref $_[0]->{'talias_updated'} )
    {
	$_[0]->{'talias_updated'} = date( $_[0]->{'talias_updated'} );
    }
    return Para::Time->get( shift->{'talias_updated'} );
}

### Methods

sub activate
{
    my( $a ) = @_;

    my $m = $Para::Frame::U;

    $a->update({
		status => $m->new_status,
	       });
    return $a;
}


sub add
{
    my( $this, $t, $name, $props ) = @_;
    my $class = ref($this) || $this;

    $name = lc trim $name;

    debug(4,"Adding alias $name");

    if( my $a = $t->alias( $name ) )
    {
	debug(4,"  Already exists. Updating");
	return $a->update( $props );
    }

    my $m = $Para::Frame::U;
    my $st_alias_add =
      "insert into talias ( talias_t, talias, talias_urlpart,
                            talias_createdby, talias_changedby,
                            talias_status, talias_autolink,
                            talias_index, talias_language,
                            talias_active )
              values ( ?, lower(?), ?, ?, ?, ?, ?, ?, ?, ? )";
    my $sth_alias_add = $Para::dbh->prepare( $st_alias_add );

    my $talias_t         = $t->id or die;
    my $talias           = $name or die;
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
			  skey  => $name,
		      });

    $t->mark_publish;


    ### Sync
    #
    delete $Para::Alias::CACHE{$name};
    delete $Para::Topic::ALIASES{$t->id};
    $t->mark_publish;

    return $t->alias( $name );
}

sub update
{
    my( $a, $props ) = @_;

    my $m = $Para::Frame::U;

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
        throw( 'denied', "Du kan inte ge aliaset en så hög status\n" );
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

    debug(4,sprintf "  updating alias %s", $a->desig);

#    debug(1,"Got ".Dumper($props));


    # Check to see if anything changed
    #
    my $changed = 0;
    if( defined $props->{'autolink'} and ($props->{'autolink'} xor $a->autolink) )
    {
	if( debug )
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
	if( debug )
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
	if( debug )
	{
	    warn sprintf( "  Language changed: %s -> %s\n",
			  ( $a->language ? $a->language->desig : '<none>' ),
			  ( $props->{'language'} ?
			    Para::Topic->get_by_id( $props->{'language'} )->desig :
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

	warn "  Setting status to $status\n";
	warn "  Existing status is ".$a->status."\n";

	# Status changed explicitly?
	#
	if( $status != $a->status )
	{
	    if( debug )
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
		debug(3,"Status changed to DENIED");
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
		debug(3,"Alias deactivated");
	    }
	}
    }

    # Return unless any changes requested
    #
    if( $changed )
    {
	debug(4,"Changes detected. Store update");
    }
    else
    {
	debug(4,"No changes");
	return $a;
    }

    # Check authorization
    #
    if( $a->status > $m->status )
    {
	if( $props->{'quiet'} )
	{
	    debug(4,"Status to low. But be quiet about it");
	    return $a;
	}
	else
	{
	    throw( 'denied',
	      sprintf( "Du har för låg nivå för att ändra aliaset %s\n",
		       $a->desig ) );
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
    my $sth = $Para::dbh->prepare( $st );

    $sth->execute( $autolink, $index, $language, $status,
		   $active, $changedby, $talias_t, $talias );

    debug(4,"updated (S$status)!");

    ### Sync
    #
    $a->reset;
    $a->topic->mark_publish;

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

    reset_hashref( $a, $rec );

    return $a;
}

sub vacuum
{
    my( $a ) = @_;

    $a->reset;
}

1;
