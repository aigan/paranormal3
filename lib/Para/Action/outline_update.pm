#  $Id$  -*-perl-*-
package Para::Action::outline_update;

use strict;
use Data::Dumper;
use Carp qw( confess );

use Para::Frame::Utils qw( throw clear_params debug );

use Para::Topic;

our $place_parent;   # The dest if it should be parent of moved obj
our $place_previous; # The dest if it should be previous of moved obj
our $placing;        # A hash of data for each row
our $row_selected;   # The row pos you selected
our $placed;         # The row pos found, based on level and selected row 
our $row_max;        # The last row pos
our $mod;            # s or a
# mod s = place as separate child to parent on row
# mod a = place after row on level (default)

sub dest; # (defind later) - The destination topic obj

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 12 )
    {
	throw('denied', "Du måste bli gesäll för att få flytta texter");
    }

    my $tid = $q->param('tid')
	or throw('incomplete', "tid param missing");

    my $t = Para::Topic->get_by_id( $tid );
    my $result = "";

    my @clear_fields = ();
#    $Para::safety = 0;


    ############################################
    # what to do?
    #
    my $do;
    $do='move_branch'  if $q->param("do_move_branch");
    $do='move_node'    if $q->param("do_move_node");
    $do='add'          if $q->param("do_add");
    $do='delete'       if $q->param("do_delete");
    $do='split'        if $q->param("do_split");
    $do='merge'        if $q->param("do_merge");
    push @clear_fields, qw(do_move_branch do_move_node
				do_add do_delete do_split do_merge);

    ############################################
    # Find the place for action
    #
    my $place = $q->param('place')
	or throw('incomplete', "Du har inte markerat vart du vill flytta texten");
    my( $row, $level, $modification ) = split('-', $place);

    $mod = $modification || 'a'; # After, not before
    push @clear_fields, 'place';


    $placed = $row_selected = $row;
    $row_max = 0;
    $place_parent = undef;
    $place_previous = undef;
    $placing = {};
    warn "Row $row_selected, level $level\n";

    for( my $i=1; my $eid = $q->param("placing_$i"); $i++ )
    {
	my $indent = $q->param("indent_$i");
	defined $indent or die "No indent_$i";
	push @clear_fields, "placing_$i", "indent_$i";


	my $entry =  Para::Topic->get_by_id( $eid );

	$placing->{$i} =
	{
	    indent => $indent,
	    row   => $i,
	    entry => $entry,
	};
#	warn "indent of $i is $indent\n";
#	warn "entry of $i is $entry\n";

	$row_max = $i;
    }

    if( $mod eq 's' )
    {
	$level --;  #Place indented to above row
    }

    for( my $seek=$row_selected; $seek > 0; $seek -- )
    {
	my $indent = $placing->{$seek}{'indent'};
	my $entry = $placing->{$seek}{'entry'};
	$placed = $seek;

	if( $level > $indent )
	{
	    $place_parent = $entry;
	    last;
	}
	elsif( $level == $indent )
	{
	    $place_previous =  $entry;
	    last;
	}
    }

    unless( $place_parent or $place_previous )
    {
	$place_parent = $t->parent;
    }

    warn("Parent: ".$place_parent->id."\n") if $place_parent;
    warn("Previous: ".$place_previous->id."\n") if $place_previous;
    warn("Placed: ".$placed."\n");
    warn("Max row: ".$row_max."\n");


    ############################################
    # Add new entry at place?
    #
    if( $do eq 'add' )
    {
	my $m = $Para::Frame::U;
	my $mid = $m->id;
	my $eid = $Para::dbix->get_nextval( "t_seq" );
	warn "Creating entry $eid\n";
	my $sth = $Para::dbh->prepare_cached("
           insert into t ( t, t_created, t_updated, t_createdby,
                           t_changedby, t_status, t_active, t_entry,
                           t_entry_parent, t_entry_imported )
           values ( ?, now(), now(), ?, ?, ?, 't', 't', ?, 1)");

	my $parent = undef;
	if( $place_parent )
	{
	    $parent = $place_parent->id;
	    $place_parent->changed;
	}
	$sth->execute( $eid, $mid, $mid, $m->new_status, $parent );

	if( $place_previous )
	{
	    my $e = Para::Topic->get_by_id( $eid );
	    $place_previous->set_next( $e );
	}

	$q->param('tid', $eid);
	$req->set_template( "/member/db/topic/edit/text.tt" );
    }


    ############################################
    # Handle each marked emtry
    #
    foreach my $eid ( reverse $q->param("thing") )
    {
	next if dest->id == $eid;
	my $e = Para::Topic->get_by_id( $eid );

	if( $do eq 'move_branch' )
	{
	    $result .= move_branch( $e );
	}
	if( $do eq 'move_node' )
	{
	    $result .= move_node( $e );
	}
    }


    push @clear_fields, 'thing';


    clear_params( @clear_fields );

    Para::Topic->commit; # Save changes

    warn "Report:\n$result\n";

    return $result;
}

sub move_branch
{
    my( $e ) = @_;

#    confess if $Para::safety++ > 1000;

    my $eid = $e->id;
    my $did = dest->id; # Destination topic id
    my $result = "";

    if( dest->child_of( $e ) )
    {
	return "Kan inte flytta grenen $eid till en del av sig själv\n";
    }

    if( $place_previous )
    {
	$result .= "* move $eid -> after $did\n";
	debug(1,"move $eid -> after $did");

	# If dest already has a "next", move that "next" to the end of
	# the string of $e
	if( my $old_next = dest->next )
	{
	    $result .= "  move $old_next->{t} after $eid\n";
	    $result .= dest->set_next(undef);
	    $result .= $e->last_entry->set_next($old_next);
	}

	$result .= dest->set_next($e);

	# We now transform childs of dest to childs of e, if e are
	# placed above the childs in the matrix
	#
	# Going through all the c below the dest in the matrix
	#
	for( my $i = $row_selected+1; $i <= $row_max; $i++ )
	{
	    my $c = $placing->{$i}{'entry'};
	    if( my $cp = $c->parent )
	    {
		my $cid = $c->id;
		my $cpid = $cp->id;
		next unless $cpid == dest->id;

		# We found a c that has dest as parent
		#
		$result .= "  Placing $cid under $eid\n";
		debug(1,"  Placing $cid under $eid");
		$result .= $c->set_parent( $e );
	    }
	}
    }

    if( $place_parent )
    {
	$result .= "* move $eid -> child of $did\n";
	debug(1,"move $eid -> child of $did");

	# decoupeling before movement
	$result .= $e->set_parent( undef );
	if( my $e_previous = $e->previous )
	{
	    $result .= $e_previous->set_next( undef );
	}

	# If there are an entry just below dest in the matrix, that
	# has the dest as a parent; place that entry as following e,
	# unless e should be placed separately ($mod='s')

	if( my $b = $placing->{$placed+1}{'entry'} )
	{
	    if( $mod ne 's' and my $bp = $b->parent )
	    {
		my $bid = $b->id;
		my $bpid = $bp->id;
		if( $bpid == dest->id )
		{
		    debug(1,"  $bid are a child of $did");
		    debug(1,"  place $eid before $bid");
		    $result .= $b->set_parent(undef);
		    $result .= $e->set_next($b);
		}
	    }
	}

	debug(1,"  Under: Set parent");
	$result .= $e->set_parent( dest );
	debug(1,"  Under: Done");
    }
    return $result;
}

sub move_node
{
    my( $e ) = @_;

#    confess if $Para::safety++ > 1000;

    my $eid = $e->id;
    my $did = dest->id; # Destination topic id


    my $result = "Kopplar loss $eid\n";
    debug(1,"Kopplar loss $eid");

    my $e_subst = undef;
    if( $e->previous )
    {
	$e_subst = $e->previous;
	$result .= $e_subst->set_next(undef );
    }
    elsif( $e->parent )
    {
	$e_subst = $e->parent;
	$result .= $e->set_parent(undef);
    }
    else
    {
	die "No subst";
    }

    $result .= "  Flyttar barn till $e_subst->{t}\n";

    # Move childs to substitute
    my $childs = $e->childs;
    foreach my $child ( @$childs )
    {
	$result .= "  make $child->{t} child to $e_subst->{t}\n";
	$result .= $child->set_parent($e_subst);
    }

    # Move next to substitute
    if( my $e_next = $e->next )
    {
	if( $e_subst->is_topic )
	{
	    $result .= "  make $e_next->{t} child to $e_subst->{t}\n";
	    $result .= $e_next->set_parent($e_subst);
	}
	else
	{
	    $result .= "  make $e_next->{t} follow $e_subst->{t}\n";
	    $result .= $e_subst->set_next( $e_next );
	}
	$result .= "  make $e_next->{t} no longer follow $eid\n";
	$result .= $e->set_next( undef );
    }

    return $result . move_branch( $e );
}

sub dest
{
    return $place_parent ? $place_parent : $place_previous;
}

1;
