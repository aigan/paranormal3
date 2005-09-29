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

    my $crits = Para::Widget::tfilter_init;

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
	my $sth = $Para::dbh->prepare("
           insert into t ( t, t_created, t_updated, t_createdby,
                           t_changedby, t_status, t_active, t_entry,
                           t_entry_parent, t_entry_imported )
           values ( ?, now(), now(), ?, ?, ?, 't', 't', ?, 1)");

	my $parent_id = undef;
	if( $place_parent )
	{
	    $parent_id = $place_parent->id;
	}

	$sth->execute( $eid, $mid, $mid, $m->new_status, $parent_id );
	my $e = Para::Topic->get_by_id( $eid );

	if( $place_previous )
	{
	    $place_previous->set_next( $e );
	}

	if( $place_parent )
	{
	    $place_parent->register_child( $e );
	}

	$q->param('tid', $eid);
	$req->set_template( "/member/db/topic/edit/text.tt" );
    }


    ############################################
    # Handle each marked emtry
    #
    foreach my $eid ( reverse $q->param("thing") )
    {
	my $d = $place_parent ? $place_parent : $place_previous;
	my $before_child = 1;
	$before_child = 0 if $mod eq 's';

	next if $d->id == $eid;
	my $e = Para::Topic->get_by_id( $eid );

	if( $do eq 'move_branch' )
	{
	    $result .= $e->move_branch({
		'dest' => $d,
		'follows' => $place_previous,
		'before_child' => $before_child,
		'crits' => $crits,
	    });
	}
	if( $do eq 'move_node' )
	{
	    $result .= $e->move_node({
		'dest' => $d,
		'follows' => $place_previous,
		'before_child' => $before_child,
		'crits' => $crits,
	    });
	}

	$e->generate_url;
    }


    clear_params('thing');

    warn "Report:\n$result\n";

    return $result;
}

1;
