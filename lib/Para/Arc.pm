#  $Id$  -*-perl-*-
package Para::Arc;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se arc class
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
use Carp qw( cluck carp croak confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Time qw( date );
use Para::Frame::Utils qw( maxof minof throw debug );
use Para::Frame::DBIx qw( pgbool );

use Para::Topic;
use Para::Arctype;
use Para::Utils qw( cache_update );
use Para::Constants qw( :all );

# This will make "if($arc)" false if the arc is 'removed'
#
use overload 'bool' => sub{ ref $_[0] and $_[0]->subj };
use overload 'eq' => sub{ undef };

sub new
{
    # Get relation(s) matchin the params
    #
    my( $this, $rec ) = @_;
    my $class = ref($this) || $this;

    unless( ref $rec eq 'HASH' )
    {
	die "Not implemented";
    }

    # TODO: Try to get this arc from an object

    my $new_arc = bless( $rec, $class );
    my $id = $new_arc->{'rel_topic'};

    if( $Para::Arc::CACHE{ $id } )
    {
	my $arc = $Para::Arc::CACHE{ $id };

	# Clear out data from arc
	#
	foreach my $prop (qw( rev rel rel_type rel_status rel_value
			      rel_comment rel_updated updated rel_changedby
			      rel_strength rel_active rel_createdby
			      rel_created created rel_indirect rel_implicit
			      ))
	{
	    delete $arc->{$prop};
	}

	foreach my $key ( keys %$new_arc )
	{
	    $arc->{$key} = $new_arc->{$key};
	}
	$new_arc = $arc;
    }

    $Para::Arc::CACHE{ $id } = $new_arc;

    return $new_arc;
}

sub get
{
    my( $this, $id, $rec ) = @_;
    my $class = ref($this) || $this;

    if( $Para::Arc::CACHE{ $id } )
    {
	return $Para::Arc::CACHE{ $id };
    }

    $rec ||= $Para::dbix->select_possible_record('from rel where rel_topic=?', $id);
    return undef unless $rec;
    return Para::Arc->new( $rec );
}

sub find
{
    # Look up the (true active) arc with specified subj, pred, obj
    #
    # Alternatively, look up all arcs matching whats been given

    my( $class, $pred, $subj, $obj_name, $props ) = @_;
    my( $obj, $literal, $all, $tid, $explain_string );

#    warn "find props: ".Dumper($props) if $DEBUG;

    $props ||= {};

    my( $all_versions, $true_versions, $false_versions,
	$active_versions, $inactive_versions, $with_comment );

    $all_versions = 1 if $props->{'all'};
    $true_versions = 1 if $props->{'true'};
    $false_versions = 1 if $props->{'false'};
    $active_versions = 1 if $props->{'active'};
    $inactive_versions = 1 if $props->{'inactive'};
    $with_comment = $props->{'comment'} if defined $props->{'comment'};

    $false_versions ||= defined $props->{'true'} ? !$props->{'true'} : 0;
    $inactive_versions ||= defined $props->{'active'} ?
      !$props->{'active'} : 0;

    my $pred_not = $props->{'pred_not'};


    my( @parts, @values );

    if( defined $pred )
    {
	my @pp = ();
	$pred = [$pred] unless ref $pred eq 'ARRAY';
	foreach my $p ( @$pred )
	{
	    $p = Para::Arctype->new($p) unless ref $p;
	    push @pp, '?';
	    push @values, $p->id;
	}
	my $ppstring = join ', ', @pp;
	push @parts,  "rel_type IN ($ppstring)";
    }
    elsif( defined $pred_not )
    {
	my @pp = ();
	$pred_not = [$pred_not] unless ref $pred_not eq 'ARRAY';
	foreach my $p ( @$pred_not )
	{
	    $p = Para::Arctype->new($p) unless ref $p;
	    push @pp, '?';
	    push @values, $p->id;
	}
	my $ppstring = join ', ', @pp;
	push @parts,  "not(rel_type IN ($ppstring))";
    }

    if( ref $obj_name eq 'Para::Topic' )
    {
	$obj = $obj_name;
    }
    elsif( defined $pred )
    {
	if( $pred->[0]->literal )
	{
	    $literal = $obj_name;
	}
	else
	{
	    $obj = Para::Topic->find_one($obj_name) if defined $obj_name;
	}
    }
    else
    {
	$literal = $obj_name;
    }

    if( defined $literal )
    {
	undef $literal if $literal eq '';
    }


    if( defined $subj )
    {
	push @parts,  "rev=?";
	push @values, $subj->id;
    }

    if( defined $obj )
    {
	push @parts,  "rel=?";
	push @values, $obj->id;
    }
    if( defined $literal )
    {
	push @parts,  "rel_value=?";
	push @values, $literal;
    }

    if( $all_versions )
    {
	if( $true_versions )
	{
	    push @parts, "rel_strength >= ".TRUE_MIN;
	}
	if( $false_versions )
	{
	    push @parts, "rel_strength < ".TRUE_MIN;
	}
	if( $active_versions )
	{
	    push @parts, "rel_active is true";
	}
	if( $inactive_versions )
	{
	    push @parts, "rel_active is false";
	}
	if( defined $with_comment )
	{
	    push @parts, "rel_comment = ?";
	    push @values, $with_comment;
	}
    }
    else
    {
	push @parts, "rel_active is true";
	push @parts, "rel_strength >= ".TRUE_MIN;
    }

    my $extra = join " and ", @parts;
#    $extra = " and " . $extra if @parts;

    my $sql = "from rel where $extra order by rel_status desc, rel_type asc";
    my $recs = $Para::dbix->select_list($sql, @values);

    if( debug )
    {
	my $value_string = join ", ", @values;
	$explain_string = "matching ($sql) with values ($value_string)";
    }

    if( $all_versions )
    {
	debug(1,"Finding all arcs $explain_string");

	my $list = [];
	foreach my $rec ( @$recs )
	{
	    push @$list, Para::Arc->new( $rec );
	}
	return $list;
    }

    debug(1,"Finding the first arc $explain_string");

    return undef unless @$recs;
    return Para::Arc->new( $recs->[0] );
}

sub create
{
    my( $class, $pred, $subj, $obj_name, $props ) = @_;

    $props ||= {};

    my $true   = defined $props->{'true'} ? $props->{'true'} : 1;
    my $active = defined $props->{'active'} ? $props->{'active'} : 0;
    my $status = defined $props->{'status'} ? $props->{'status'} :
      $active ? $Para::Frame::U->new_status : 0;
    my $by = defined $props->{'by'} ? $props->{'by'} : $Para::Frame::U;
    my $strength = defined $props->{'strength'} ? $props->{'strength'} : $true ? TRUE_NORM : 0;
    my $comment = defined $props->{'comment'} ? $props->{'comment'} : undef;
    my $implicit = defined $props->{'implicit'} ? $props->{'implicit'} : 0;
    my $indirect = defined $props->{'indirect'} ? $props->{'indirect'} : 0;
    my $changed = $props->{'changed'};
    my $now = localtime;
    my $u = $Para::Frame::U;

    $true = ( $strength >= TRUE_MIN ? 1 : 0 );
    $pred = Para::Arctype->new($pred) unless ref $pred;
    $subj = Para::Topic->get_by_id($subj) unless ref $subj;
    $by   = Para::Member->get($by) unless ref $by;

    # Let's see if a similar arc already exists
    my $create_props = {};
    if( $true )
    {
	$create_props->{'true'} = 1;
    }
    else
    {
	$create_props->{'false'} = 0;
    }

    $create_props->{'comment'} = $comment;
    my $arcs = Para::Arc->find( $pred, $subj, $obj_name,
			     {
			      all => 1,
			      true => $true,
			      comment => $comment,
			     });

    if( debug )
    {
	my $desc = "$$: Looking for arc that";

	$desc .= $true ? ' are true' : ' are false';
	$desc .= $active ? ', active' : ', inactive';
	$desc .= " with status $status\n";
	warn $desc;
    }

    # May find inactive arc. Make it active. Or vice versa
    if( @$arcs )
    {
	my $arc = $arcs->[0];
	debug(0, sprintf( "Found existing %s, activation %d\n", $arc->desig, $arc->active),1);

	# Cases:
	# 1. Found active, want inactive
	# 2. Found active, want active, other status
	# 3. Found inactive, want inactive, other status
	# 4. Found inactive, want active

	if( $arc->active and not $active )
	{
	    debug(1,"Found active, want inactive\n");
	    unless( $u->status >= S_NORMAL )
	    {
		throw( 'denied', "Du har för låg nivå" );
	    }

	    unless( $u->status >= $arc->status )
	    {
		throw( 'denied', "You can't modify ".$arc->desig );
	    }

	    $arc->deactivate( $status );
	}
	elsif( $arc->active and $active and
	       $status > $arc->status )
	{
	    debug(1,"Found active, want active with higher status");
	    unless( $u->status >= $arc->status and
		    $u->status >= $status )
	    {
		throw( 'denied', "Du har för låg nivå" );
	    }

	    debug(1,sprintf "Trying to activate arc %s", $arc->desig);
	    $arc->activate( $status );
	}
	elsif( $arc->inactive and not $active and
	       $arc->status != $status )
	{
	    debug(1,"Found inactive, want inactive with other status");
	    unless( $u->status >= S_NORMAL )
	    {
		throw( 'denied', "Du har för låg nivå" );
	    }

	    $arc->deactivate( $status );
	}
	elsif( $arc->inactive and $active )
	{
	    debug(1,"Found inactive, want active");
	    # No authorization required

	    $arc->activate( $status );
	}
	else
	{
	    debug(1,"No change to arc");
	}

	debug(-1);

	return $arc;
    }
    else
    {
	debug(1,"none found");
    }

    my( $obj, $literal, $rel );
    if( $pred->literal )
    {
	$literal = $obj_name;
	undef $literal if $literal eq '';
    }
    else
    {
	$obj = Para::Topic->find_one($obj_name);

	if( $subj->equals( $obj ) )
	{
	    cluck "Cyclic relation about to be created";
	    throw('denied', "Inga cykliska relationer tillåtna");
	}


	$rel = $obj->id;
	$obj->mark_publish;
    }

    my $sth = $Para::dbh->prepare(
	  "insert into rel (rel_topic, rev, rel, rel_type, rel_status,
                            rel_updated, rel_changedby,
                            rel_created, rel_createdby, rel_strength,
                            rel_active, rel_value, rel_comment,
                            rel_implicit, rel_indirect)
           values (?, ?, ?, ?, ?, now(), ?, now(), ?, ?, ?, ?, ?, ?, ?)");

    my $rid = $Para::dbix->get_nextval('t_seq');
    $sth->execute( $rid, $subj->id, $rel, $pred->id,
		   $Para::Frame::U->new_status, $by->id, $by->id,
		   $strength, pgbool($active), $literal,
		   $comment, pgbool($implicit), pgbool($indirect) );

    $subj->mark_publish;

    $obj->reset if $obj;
    $subj->reset;

    my $arc = Para::Arc->get( $rid );
    if( $active and $strength >= TRUE_MIN )
    {
	$arc->reject_other_versions;
    }
    $arc->create_check;
    $$changed ++ if ref $changed; # Increment things changed

    $by->score_change( 'topic_connected', 1 );

    warn sprintf "Created %s\n", $arc->desig;
    return $arc;
}

#########################################################

sub id
{
    return shift->{'rel_topic'};
}

sub pred_id
{
    my( $arc ) = @_;
    return $arc->{'rel_type'};
}

sub node
{
    my( $arc, $dir ) = @_;
    $dir or confess "deprecated: dir missing";
    return Para::Topic->get_by_id( $arc->{$dir} );
}

sub name
{
    my( $arc, $dir ) = @_;
    $dir ||= $arc->{'dir'};
    my $type = $arc->type;
    return $type->name($dir);
}

sub type
{
    my( $arc ) = @_;

    unless( $arc->{'type'} )
    {
	$arc->{'type'} = Para::Arctype->new( $arc->{'rel_type'} );
    }
    return $arc->{'type'};
}
sub pred { shift->type(@_) }


sub relt
{
    return undef unless $_[0]->{'rel'};
    return Para::Topic->get_by_id( $_[0]->{'rel'} );
}
sub obj { shift->relt(@_) }

sub revt {Para::Topic->get_by_id( $_[0]->{'rev'} ) }
sub subj {Para::Topic->get_by_id( $_[0]->{'rev'} ) }



sub value
{
    return $_[0]->{'rel_value'};
}

sub value_string
{
    my( $arc ) = @_;

    if( $arc->obj )
    {
	return $arc->obj->desig;
    }
    else
    {
	return sprintf("'%s'", $arc->value||'<undef>');
    }
}

sub comment
{
    return $_[0]->{'rel_comment'};
}

sub status  { shift->{'rel_status'} }
sub active  { shift->{'rel_active'} }
sub inactive  { not shift->{'rel_active'} }
sub created
{
    return $_[0]->{'created'} ||= date( $_[0]->{'rel_created'} );
}
sub updated
{
    return $_[0]->{'updated'} ||= date( $_[0]->{'rel_updated'} );
}
sub strength { shift->{'rel_strength'} }

sub true { shift->strength >= TRUE_MIN ? 1 : 0 }
sub false { shift->strength >= TRUE_MIN ? 0 : 1 }

sub desig
{
    my( $arc ) = @_;

    return sprintf("%d: %s -- %s --> %s (%d-%d)",
		   $arc->id,
		   $arc->subj->desig,
		   $arc->pred->name('rel'),
		   $arc->value_string,
		   $arc->status,
		   $arc->strength,
		  );
}

sub equals
{
    my( $arc, $arc2 ) = @_;

    croak "mismatch" unless ref $arc2 eq 'Para::Arc';

    if( $arc->id == $arc2->id )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub implicit
{
    return shift->{'rel_implicit'};
}

sub explicit
{
    return not shift->{'rel_implicit'};
}

sub set_explicit
{
    shift->set_implicit(0);
}

sub set_implicit
{
    my( $arc, $val ) = @_;

    # sets to 'true' if called without arg
    defined $val or $val = 1;

    $val = $val ? 1 : 0;
    return if $val == $arc->implicit;

    my $desc_str = $val ? 'implicit' : 'explicit';
#    warn sprintf "%d: Set %s for arc %s\n",
#      $$, $desc_str, $arc->desig;

    my $arc_id    = $arc->id;
    my $mid       = $Para::Frame::U->id;
    my $now       = localtime;

    my $sth = $Para::dbh->prepare("update rel set rel_implicit=?, ".
				   "rel_updated=?, rel_changedby=? ".
				   "where rel_topic=?");
    $sth->execute(pgbool($val), $now->cdate, $mid, $arc_id);

    $arc->{'rel_updated'} = $arc->{'updated'} = $now;
    $arc->{'rel_changedby'} = $mid;
    $arc->{'rel_implicit'} = $val;

    cache_update;

    return $val;
}


sub indirect
{
    return shift->{'rel_indirect'};
}

sub direct
{
    return not shift->{'rel_indirect'};
}

sub set_direct
{
    shift->set_indirect(0);
}

sub set_indirect
{
    my( $arc, $val ) = @_;

    # sets to 'true' if called without arg
    defined $val or $val = 1;

    $val = $val ? 1 : 0; # normalize
    return if $val == $arc->indirect; # Return if no change

    my $desc_str = $val ? 'indirect' : 'direct';
#    warn sprintf "%d: Set %s for arc %s\n",
#      $$, $desc_str, $arc->desig;

    my $arc_id    = $arc->id;
    my $mid       = $Para::Frame::U->id;
    my $now       = localtime;

    my $sth = $Para::dbh->prepare("update rel set rel_indirect=?, ".
				   "rel_updated=?, rel_changedby=? ".
				   "where rel_topic=?");
    $sth->execute(pgbool($val), $now->cdate, $mid, $arc_id);

    $arc->{'rel_updated'} = $arc->{'updated'} = $now;
    $arc->{'rel_changedby'} = $mid;
    $arc->{'rel_indirect'} = $val;

#    if( not $val and $arc->implicit ) # direct ==> explicit
#    {
#	# We can change this here because validation check is done
#	# before call to set_indirect
#
#	warn "$$:   No arc can be both direct and implicit\n";
#	warn "$$:   This arc must change or be removed now!\n";
#    }

    cache_update;

    return $val;
}

sub replace
{
    my( $arc, $pred, $subj, $obj_name, $props ) = @_;

    $pred = Para::Arctype->new($pred) unless ref $pred;
    $subj = Para::Topic->get_by_id($subj) unless ref $subj;

    my $m = $Para::Frame::U;
    if( $arc->status > $m->status )
    {
	throw( 'denied', sprintf "Arc %s has status %d",
	  $arc->desig, $arc->status );
    }

    my $arc2 = Para::Arc->create( $pred, $subj, $obj_name, $props );

    unless( $arc->equals( $arc2 ) )
    {
	$arc->deactivate( S_REPLACED );
    }
    return $arc2;
}

sub activate
{
    my( $arc, $status ) = @_;

    my $m = $Para::Frame::U;
    $status ||= $m->new_status;
    my $now       = localtime;
    my $mid       = $Para::Frame::U->id;

    confess sprintf("Wrong status %d for activating arc %s\n", $status, $arc->desig) if $status <= S_PROPOSED;
#    throw 'action', sprintf("Wrong status %d for activating arc %s\n", $status, $arc->desig) if $status <= S_PROPOSED;

    if( $arc->status > $m->status )
    {
	throw( 'denied', sprintf "Arc %s has status %d",
	  $arc->desig, $arc->status );
    }

    return if $arc->active and $arc->status == $status;
    return if $arc->disregard;

    warn sprintf "$$: Activating %s\n", $arc->desig; ### DEBUG

    # Fix both ends for reflexive relations
    my $rarc; # Holds the corresponding rel
    if( $arc->type->id == 0 )
    {
	$rarc = $arc->obj->arc({ pred=>0, obj=>$arc->subj });
    }

    if( $rarc ) # Reverse relation
    {
	warn sprintf "$$:   activating reverse %s\n", $rarc->desig; ### DEBUG
	my $sth = $Para::dbh->prepare(
	  "update rel set rel_active=true, rel_status=?,
           rel_changedby=?, rel_updated=?
           where rel_topic=?");

	$sth->execute( $status, $mid, $now->cdate, $rarc->id );
    }

    my $sth = $Para::dbh->prepare(
	  "update rel set rel_active=true, rel_status=?,
           rel_changedby=?, rel_updated=?
           where rel_topic=?");

    debug(1,"Updating arc status to $status");
    $sth->execute( $status, $mid, $now->cdate, $arc->id );

    if( $status > $arc->status )
    {
	my $chart = ($status == S_FINAL ? 'thing_finalised' : 'thing_accepted');
	$arc->created_by->score_change($chart, 1);
	$Para::Frame::U->score_change('accepted_thing', 1);
    }

    $arc->mark_publish;
    $arc->reset;
    debug(1," -- Should we deactivate other versions?");
    if( $arc->true )
    {
	debug(1," --   yes");
	$arc->reject_other_versions;
    }
    $arc->create_check;

    cache_update();
}

sub reject_other_versions
{
    my( $arc ) = @_;

    foreach my $arcv (@{ $arc->versions })
    {
#	warn sprintf " --   Deactivating %d?\n", $arcv->id;
	next if $arcv->equals( $arc );
	next if $arcv->status <= S_REPLACED and $arcv->inactive;

	## Check if we have authority to deactivate
	if( $arcv->status > $Para::Frame::U->status )
	{
	    throw( 'denied', sprintf "Arc %s has status %d",
	      $arc->desig, $arc->status );
	}

#	warn " --     yes\n";
	$arcv->deactivate( S_REPLACED );
    }
}


# We KNOW this is going to be deactivated. Finish by finding out what
# effect that has on other things
#
sub deactivate
{
    my( $arc, $status ) = @_;

    $status ||= S_DENIED;
    my $now       = localtime;
    my $mid       = $Para::Frame::U->id;

    die "Wrong status" if $status >= S_PENDING;

    # Authorization should be checked BEFORE we call deactivate!!!

    # We could run deactivate even if already inactive
    return if $arc->inactive and $arc->status == $status;
    return if $arc->disregard;

    warn sprintf "$$: Deactivating %s\n", $arc->desig; ### DEBUG

    # Fix both ends for reflexive relations
    my $rarc; # Holds the corresponding rel
    if( $arc->type->id == 0 )
    {
	$rarc = $arc->obj->arc({ pred=>0, obj=>$arc->subj });
    }

    if( $rarc ) # Reverse relation
    {
	warn sprintf "$$:   deactivating reverse %s\n", $rarc->desig; ### DEBUG
	my $sth = $Para::dbh->prepare(
	  "update rel set rel_active=false, rel_status=?,
           rel_changedby=?, rel_updated=?
           where rel_topic=?");

	$sth->execute( $status, $mid, $now->cdate, $rarc->id );
    }

    my $sth = $Para::dbh->prepare(
	  "update rel set rel_active=false, rel_status=?,
           rel_changedby=?, rel_updated=?
           where rel_topic=?");

    $sth->execute( $status, $mid, $now->cdate, $arc->id );

    if( $status < $arc->status )
    {
	$arc->created_by->score_change('thing_rejected', 1);
	$Para::Frame::U->score_change('rejected_thing', 1);
    }

    $arc->mark_publish;
    $arc->reset;

    # Has another arc taken it's place?
    my $arcs = Para::Arc->find( $arc->pred, $arc->subj, $arc->obj,
				 {
				  all => 1,
				  true => $arc->true,
				  active => 1,
				 });
    if( @$arcs )
    {
	# Another arc has taken it's place.
    }
    elsif( $arc->true )
    {
	# A true arc has been deactivated
	if( $arc->validate_check )
	{
	    # The arc was deactivated but can be infered
	    die sprintf("Arc %s was asked to deactivate, but can be infered",
		       $arc->desig);
	}
	else
	{
	    $arc->remove_check;
	}
    }

    cache_update();
}

# Remove arc if it was implicit but isn't anymore
#
sub deactivate_implicit
{
    my( $arc ) = @_;

    return if $arc->inactive;
    return if $arc->false;

    # also fixes direct/indirect flag
    return if $arc->validate_check;

    return if $arc->explicit;

    $arc->deactivate;
}

sub vacuum
{
    my( $arc ) = @_;

    # Only fixes THIS arc.  This method is called by Topic->vacuum()
    return if $arc->{'disregard'};

    if( $arc->active and  $arc->status < S_PENDING)
    {
	# Before this, we made the topic PENDING. Now we deactivate
	warn sprintf "$$: arc %s has the wrong status\n", $arc->desig;
	$arc->deactivate;
    }
    elsif( $arc->inactive and $arc->status >= S_PENDING )
    {
	warn sprintf "$$: arc %s has the wrong status\n", $arc->desig;
	$arc->deactivate( S_REPLACED );
    }

    $arc->deactivate_implicit; ## Only removes if not valid
    $arc->create_check;  ## Only if still true active

    return $arc;
}

sub mark_publish
{
    my( $arc ) = @_;

    $arc->obj and $arc->obj->mark_publish;
    $arc->subj->mark_publish;
}

sub reset
{
    my( $arc, $rec ) = @_;

    my $obj = $arc->obj;
    $arc->subj->reset;
    $obj and $obj->reset;

    # Refresh this arc from DB
    #
    $rec ||= $Para::dbix->select_record('from rel where rel_topic=?', $arc->id);
    return Para::Arc->new( $rec );
}

sub versions
{
    my( $arc ) = @_;

    return Para::Arc->find( $arc->pred,
			   $arc->subj,
			   $arc->obj || $arc->value,
			 {
			  all => 1,
			 },
			 );
}

sub disregard
{
    my( $arc ) = @_;
#    if($arc->{'disregard'})
#    {
#	warn "$$: Disregarding arc $arc->{rel_topic}: ".$arc->as_string."\n";
#	warn "$$:   value is $arc->{'disregard'}\n";
#    }

    return $arc->{'disregard'};
}

sub created_by
{
    Para::Member->get( shift->{'rel_createdby'} );
}

sub updated_by
{
    Para::Member->get( shift->{'rel_changedby'} );
}

sub infered
{
    my( $arc ) = @_;

    return 1 if $arc->active and $arc->validate_check;
    return 0;
}

sub remove
{
    my( $arc, $arg ) = @_;
    #
    # Return number of arcs removed

    $arg ||= '';
    unless( $arg eq 'force' )
    {
	confess "infered arc" if $arc->infered;
    }

    $arc->remove_check;

    my $arc_id = $arc->id;
    warn sprintf "%d: Removed arc %s\n",
      $$, $arc->desig;

    my $sth = $Para::dbh->prepare("delete from rel where rel_topic=?");
    $sth->execute($arc_id);
    $arc->{disregard} ++;

    # Same as arc->reset(), but arc is now gone. Only fix subj/obj
    my $obj = $arc->obj;
    $arc->subj->reset;
    $obj and $obj->reset;

    # Clear out data from arc (and arc in cache)
    #
    Para::Arc->new({
		   rel_topic => $arc->id,
		   disregard => 1,
		  });

    return 1; # One arc removed
}

sub as_string
{
    my( $arc ) = @_;

    return sprintf("%s --%s--> %s", $arc->subj->desig, $arc->pred->name('rel'), $arc->value_string);
}


sub explain
{
    my( $arc ) = @_;

    # Explain how the arc is infered

    if( $arc->indirect )
    {
	if( $arc->validate_check )
	{
	    warn "Inference recorded\n";
	    # All good
	}
	else
	{
	    warn "Couldn't be infered\n";
	    if( $arc->implicit )
	    {
		$arc->deactivate;
	    }
	}
    }
    else
    {
	warn "Not indirect\n";
    }

    return $arc->{'explain'};
}



###############################################################
#
# Check if we should infere

# for validation and remove: marking the arcs as to be disregarded in
# those methods. Check for $arc->disregard before considering an arc

sub validate_check
{
    my( $arc ) = @_;
    #
    # Return true if this arc can be infered from other arcs,
    # regardless of the status of this arc.

    $arc->{'disregard'} ++;
#    warn sprintf("Set disregard arc %s (now %s)\n", $arc->id,  $arc->{'disregard'});

    # Room for textual explenation of inferences
    $arc->{'explain'} = [];

    my $validated = 0;
    my $rtid = $arc->pred->id;
#    warn sprintf "%d: validate_check %s\n", $$, $arc->as_string;

    if( $rtid == 1) # är
    {
	$validated += $arc->validate_infere(1,2,1);
	$validated += $arc->validate_infere(42,41,1);
    }
    elsif( $rtid == 2) # är en sorts
    {
	$validated += $arc->validate_infere(2,2,2);
    }
    elsif( $rtid == 3) # är underämne till
    {
	$validated += $arc->validate_infere(1,3,3);
	$validated += $arc->validate_infere(2,3,3);
	$validated += $arc->validate_infere(3,3,3);
	$validated += $arc->validate_infere(31,3,3);
    }
    elsif( $rtid == 4) # enligt
    {
	$validated += $arc->validate_infere(3,4,4);
    }
    elsif( $rtid == 7) # är medlem i
    {
	$validated += $arc->validate_infere(1,29,7);
	$validated += $arc->validate_infere(7,31,7);
    }
    elsif( $rtid == 12) # är intresserad av
    {
	$validated += $arc->validate_infere(7,12,12);
	$validated += $arc->validate_infere(1,12,12);
	$validated += $arc->validate_infere(12,2,12);
	$validated += $arc->validate_infere(2,12,12);
	$validated += $arc->validate_infere(12,12,12);
    }
    elsif( $rtid == 29) # är en sorts medlem i
    {
	$validated += $arc->validate_infere(2,29,29);
    }
    elsif( $rtid == 31) # är en del av
    {
	$validated += $arc->validate_infere(31,31,31);
    }
    elsif( $rtid == 32) # är oftast en del av
    {
	$validated += $arc->validate_infere(32,2,32);
    }
    elsif( $rtid == 42) # är exemplar av något som är
    {
	$validated += $arc->validate_infere(40,1,42);
    }
    elsif( $rtid == 0) # är relaterad till
    {
	$validated += $arc->validate_reflexive(0);
    }

    # Mark arc if it's indirect or not
    $arc->set_indirect( $validated );


    $arc->{'disregard'} --;
#    warn sprintf("Unset disregard arc %s (now %s)\n", $arc->id,  $arc->{'disregard'});
    return $validated;
}

sub create_check
{
    my( $arc ) = @_;
    #
    # Create new arcs infered from this arc

    # TODO: See that existing FALSE arcs is turned true if they can be
    # infered

    # TODO: Do not make inference based on arcs with low status. Only
    # for normal or higher arcs


    return unless $arc->active;
    return unless $arc->true;

    if( $arc->status < S_PENDING )
    {
	confess "create_check for arc with to low status: ".$arc->desig;
    }

    my $rtid = $arc->pred->id;
#    warn "$$: create_check $rtid\n";

    # Col 1 -> rel
    # Col 2 -> rev

    if( $rtid == 1 ) # är
    {
	$arc->create_infere_rel(1,2,1); # B> 1 2 1
	$arc->create_infere_rel(1,3,3); # B> 1 3 3
	$arc->create_infere_rel(1,29,7);
	$arc->create_infere_rel(1,12,12);
	$arc->create_infere_rev(40,1,42);
    }
    elsif( $rtid == 2 ) # är en sorts
    {
	$arc->create_infere_rev(2,2,2); # A< 2 2 2
	$arc->create_infere_rel(2,2,2); # B> 2 2 2
	$arc->create_infere_rev(1,2,1); # A< 2 1 1
	$arc->create_infere_rel(2,3,3); # A> 2 3 3
 	$arc->create_infere_rev(32,2,32);
	$arc->create_infere_rel(2,29,29);
	$arc->create_infere_rev(12,2,12);
	$arc->create_infere_rel(2,12,12);
    }
    elsif( $rtid == 3 ) # är underämne till
    {
	$arc->create_infere_rev(3,3,3); # A< 3 3 3
	$arc->create_infere_rel(3,3,3); # B> 3 3 3
	$arc->create_infere_rev(1,3,3); # A< 3 1 3
	$arc->create_infere_rev(2,3,3); # B< 3 2 3
	$arc->create_infere_rel(3,4,4);
	$arc->create_infere_rev(31,3,3);
    }
    elsif( $rtid == 4 ) # enligt
    {
	$arc->create_infere_rev(3,4,4);
    }
    elsif( $rtid == 7 ) # är medlem i
    {
	$arc->create_infere_rel(7,31,7);
	$arc->create_infere_rel(7,12,12);
    }
    elsif( $rtid == 12 ) # är intresserad av
    {
	$arc->create_infere_rev(7,12,12);
	$arc->create_infere_rev(1,12,12);
	$arc->create_infere_rel(12,2,12);
	$arc->create_infere_rev(2,12,12);
	$arc->create_infere_rev(12,12,12);
	$arc->create_infere_rel(12,12,12);
    }
    elsif( $rtid == 29 ) # är en sorts medlem i
    {
	$arc->create_infere_rev(1,29,7);
	$arc->create_infere_rev(2,29,29);
    }
    elsif( $rtid == 31 ) # är en del av
    {
	$arc->create_infere_rev(7,31,7);
	$arc->create_infere_rel(31,31,31);
	$arc->create_infere_rev(31,31,31);
	$arc->create_infere_rel(31,3,3);
    }
    elsif( $rtid == 32 ) # är oftast en del av
    {
	$arc->create_infere_rel(32,2,32);
    }
    elsif( $rtid == 40 ) # är exemplar av
    {
	$arc->create_infere_rel(40,1,42);
    }
    elsif( $rtid == 41 ) # exemplar är
    {
	$arc->create_infere_rev(42,41,1);
    }
    elsif( $rtid == 42 ) # är exemplar av något som är
    {
	$arc->create_infere_rel(42,41,1);
    }
    elsif( $rtid == 0 ) # är relaterad till
    {
	$arc->create_reflexive(0);
    }
 }

sub remove_check
{
    my( $arc ) = @_;
    #
    # remove implicit arcs infered from this arc

    # arc removed (or changed) *after* this sub

    $arc->{'disregard'} ++;
#    warn "Set disregard arc $arc->{rel_topic}\n";
    my $rtid = $arc->pred->id;
#    warn "$$: remove_check $rtid\n";

    # Col 1 -> rel
    # Col 2 -> rev

    if( $rtid == 1 ) # är
    {
	$arc->remove_infere_rel(1,2,1);
	$arc->remove_infere_rel(1,3,3);
	$arc->remove_infere_rel(1,29,7);
	$arc->remove_infere_rel(1,12,12);
	$arc->remove_infere_rev(40,1,42);
    }
    elsif( $rtid == 2 ) # är en sorts
    {
	$arc->remove_infere_rev(2,2,2);
	$arc->remove_infere_rel(2,2,2);
	$arc->remove_infere_rev(1,2,1);
	$arc->remove_infere_rel(2,3,3);
	$arc->remove_infere_rev(32,2,32);
	$arc->remove_infere_rel(2,29,29);
	$arc->remove_infere_rev(12,2,12);
	$arc->remove_infere_rel(2,12,12);
    }
    elsif( $rtid == 3 ) # är underämne till
    {
	$arc->remove_infere_rev(3,3,3);
	$arc->remove_infere_rel(3,3,3);
	$arc->remove_infere_rev(1,3,3);
	$arc->remove_infere_rev(2,3,3);
	$arc->remove_infere_rel(3,4,4);
	$arc->remove_infere_rev(31,3,3);
    }
    elsif( $rtid == 4 ) # enligt
    {
	$arc->remove_infere_rev(3,4,4);
    }
    elsif( $rtid == 7 ) # är medlem i
    {
	$arc->remove_infere_rel(7,31,7);
	$arc->remove_infere_rel(7,12,12);
    } 
    elsif( $rtid == 12 ) # är intresserad av
    {
	$arc->remove_infere_rev(7,12,12);
	$arc->remove_infere_rev(1,12,12);
	$arc->remove_infere_rel(12,2,12);
	$arc->remove_infere_rev(2,12,12);
    } 
    elsif( $rtid == 29 ) # är en sorts medlem i
    {
	$arc->remove_infere_rev(1,29,7);
	$arc->remove_infere_rev(2,29,29);
    }
    elsif( $rtid == 31 ) # är en del av
    {
	$arc->remove_infere_rev(7,31,7);
	$arc->remove_infere_rel(31,31,31);
	$arc->remove_infere_rev(31,31,31);
	$arc->remove_infere_rel(31,3,3);
    }
    elsif( $rtid == 32 ) # är oftast en del av
    {
	$arc->remove_infere_rel(32,2,32);
    }
    elsif( $rtid == 40 ) # är exemplar av
    {
	$arc->remove_infere_rel(40,1,42);
    }
    elsif( $rtid == 41 ) # exemplar är
    {
	$arc->remove_infere_rev(42,41,1);
    }
    elsif( $rtid == 42 ) # är exemplar av något som är
    {
	$arc->remove_infere_rel(42,41,1);
    }
    elsif( $rtid == 0 ) # är relaterad till
    {
	$arc->remove_reflexive(0);
    }

#    warn "Unset disregard arc $arc->{rel_topic}\n";
    $arc->{'disregard'} --;
}


###################################################################

# A full vacuum sweep of the DB will run validate and then
# create_check for each arc.  In order to catch tied circular
# dependencies we will in validation check validate dependencies til
# we found a base in explicit arcs.

sub validate_infere
{
    my( $arc, $p1, $p2, $p3 ) = @_;
    #
    # A3B & A1C & C2D & D=B
    # A1B & B2C -> A3C
    # > 1 2 3

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $subj->rel({type => $p1 })->arcs })
    {
	next if disregard $arc2;
	next if $arc2->id == $arc->id;
	next unless $arc2->status >= S_NORMAL;

	foreach my $arc3 (@{  $arc2->obj->rel({type => $p2 })->arcs })
	{
	    next if disregard $arc3;
	    next unless $arc3->status >= S_NORMAL;

	    if( $arc3->obj->id == $obj->id )
	    {
		my $exp =
		{
		 a1 => $arc2,
		 a2 => $arc3,
		 a3 => $arc,
		};
		push @{$arc->{'explain'}}, $exp;
		return 1;
	    }
	}
    }
    return 0;
}

sub validate_reflexive
{
    my( $arc, $p ) = @_;

    ### One should be implicit but both should be direct

    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    # The explicit can't be infered from the implicit
    return 0 if $arc->explicit;

    foreach my $arc2 (@{ $obj->rel({type => $p})->arcs })
    {
	next if disregard $arc2;
	next unless $arc2->status >= S_NORMAL;

	return 1 if $arc2->obj->id == $subj->id;
    }

    return 0;
}

sub create_infere_rev
{
    my( $arc, $p1, $p2, $p3 ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    return 0 unless $arc->status >= S_NORMAL;

    foreach my $arc2 (@{  $subj->rev({type => $p1})->arcs })
    {
	next unless $arc2->status >= S_NORMAL;

	debug(sprintf "arc2 %s, activation %d\n ", $arc2->desig, $arc2->active);
	if( $arc2->status < S_PENDING )
	{
	    warn "Found an arc with wrong status during inference. Vacuuming!\n";
	    $arc2->subj->vacuum;
	    next;
	}
	my $arc3 = Para::Arc->find( $p3, $arc2->subj, $obj);
	unless( $arc3 )
	{
	    my $strength = minof( $arc->strength, $arc2->strength );
	    $strength = int((0.9 * ($strength - TRUE_MIN))+TRUE_MIN);
	    my $status = minof( $arc->status, $arc2->status );

	    if( $arc2->subj->equals( $obj ) )
	    {
		warn sprintf "Will not create cyclic reference for %s\n",
		  $obj->desig;
		next;
	    }

	    $arc3 = Para::Arc->create($p3, $arc2->subj, $obj,
				    {
				     implicit => 1,
				     strength => $strength,
				     status   => $status,
				     active   => 1,
				     indirect => 1,
				     by       => -1,
				    });
	}
	$arc3->set_indirect;
    }
}

sub create_infere_rel
{
    my( $arc, $p1, $p2, $p3 ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    return 0 unless $arc->status >= S_NORMAL;

    foreach my $arc2 (@{  $obj->rel({type => $p2})->arcs })
    {
	next unless $arc2->status >= S_NORMAL;

	debug(1,sprintf "arc2 %d: %s, activation %d\n", $arc2->id, $arc2->desig, $arc2->active);
	if( $arc2->status < S_PENDING )
	{
	    warn "Found an arc with wrong status during inference. Vacuuming!\n";
	    $arc2->subj->vacuum;
	    next;
	}
	my $arc3 = Para::Arc->find( $p3, $subj, $arc2->obj);
	if( $arc3 )
	{
	    debug(1,"Found existing arc to make infered: ".$arc3->desig);
	}
	else
	{
	    my $strength = minof( $arc->strength, $arc2->strength );
	    $strength = int((0.9 * ($strength - TRUE_MIN))+TRUE_MIN);
	    my $status = minof( $arc->status, $arc2->status );

	    if( $subj->equals( $arc2->obj ) )
	    {
		warn sprintf "Will not create cyclic reference for %s\n",
		  $subj->desig;
		next;
	    }

	    $arc3 = Para::Arc->create($p3, $subj, $arc2->obj,
				    {
				     implicit => 1,
				     strength => $strength,
				     status   => $status,
				     active   => 1,
				     indirect => 1,
				     by       => -1,
				    });
	}
	$arc3->set_indirect;
    }
}

sub create_reflexive
{
    my( $arc, $p ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;
    return 1 if $arc->implicit; # Prevent infinite loop
    return 0 unless $arc->status >= S_NORMAL;

    my $m = Para::Member->get(-1);

    my $arc2 = Para::Arc->find( $p, $obj, $subj );
    unless( $arc2 )
    {
	my $strength = $arc->strength;
	my $status = $arc->status;

	if( $subj->equals( $obj ) )
	{
	    warn sprintf "Will not create cyclic reference for %s\n",
	      $obj->desig;
	    next;
	}

	$arc2 = Para::Arc->create($p, $obj, $subj,
			       {
				implicit => 1,
				indirect => 1,
				strength => $strength,
				status   => $status,
				active   => 1,
				by       => -1,
			       });
    }
}

sub remove_infere_rev
{
    my( $arc, $p1, $p2, $p3 ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $subj->rev({type => $p1})->arcs })
    {
	next if disregard $arc2;
	my $arc3 = Para::Arc->find( $p3, $arc2->subj, $obj );
	if( $arc3 )
	{
	    next if disregard $arc3;
	    $arc3->deactivate_implicit;
	}
    }
}

sub remove_infere_rel
{
    my( $arc, $p1, $p2, $p3 ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $obj->rel({type => $p2})->arcs })
    {
	next if disregard $arc2;
	my $arc3 = Para::Arc->find( $p3, $subj, $arc2->obj );
	if( $arc3 )
	{
	    next if disregard $arc3;
	    $arc3->deactivate_implicit;
	}
    }
}

sub remove_reflexive
{
    my( $arc, $p ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    my $arc2 = Para::Arc->find( $p, $obj, $subj );
    if( $arc2 and not $arc2->disregard )
    {
	$arc2->deactivate_implicit;
    }
}

################################################

1;
