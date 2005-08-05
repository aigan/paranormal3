#  $Id$  -*-perl-*-
package Para::Arcs;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se arcs list class
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
use Carp qw( confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim debug );

use Para::Topic;
use Para::Arc;
use Para::Constants qw( :all );

sub new
{
    my( $this, $props ) = @_;
    my $class = ref($this) || $this;

    $props->{'content'} = [];
    return bless $props, $class;
}



### Class methods

sub init_rel
{
    # Look up all (true active) arcs for this topic
    #
    my( $class, $t ) = @_;

#    warn "find rels for $t->{t}\n";

    my $arcs =
    {
     t => $t,
     dir => 'rel',
     content => [],
    };

    # Set up indexes
    #
    my $topic_idx = $arcs->{'topic_idx'} ||= {};
    my $reltype_idx = $arcs->{'reltype_idx'} ||= {};
    my $reltype_direct_idx = $arcs->{'reltype_direct_idx'} ||= {};


    # Could include active relations to inactive topics
    my $rels = $Para::dbix->select_list("from rel where rev=? and rel_active is true
                            and rel_strength >= ?", $t->id, TRUE_MIN);
    foreach my $rel ( @$rels )
    {
	defined $rel->{'rel_type'} or die "rel_type undef: ".Dumper( $rel );
	my $type = $rel->{'rel_type'};
	my $relt = $rel->{'rel'};
	my $relval = $rel->{'rel_value'};
	my $arc =  Para::Arc->new($rel);

	## Insert context info in arc object
	$arc->{'dir'} = 'rel';

	## Full idx
	push @{ $arcs->{'content'} }, $arc;

	## Topic idx
	if( $relt )
	{
	    $topic_idx->{$relt} ||= $class->new({
		dir    => 'rel',
		select => 'topic',
		topic  => $rel,
	    });
	    push @{ $topic_idx->{$relt}{'content'} }, $arc;
	}

	## Reltype idx
	$reltype_idx->{$type} ||= $class->new({
	    dir     => 'rel',
	    select  =>'reltype',
	    reltype => $type,
	});
	push @{ $reltype_idx->{$type}{'content'} }, $arc;

	## Reltype direct idx
	unless( $rel->{'rel_indirect'} )
	{
	    $reltype_direct_idx->{$type} ||= $class->new({
		dir     => 'rel',
		select  =>'reltype',
		reltype => $type,
	    });
	    push @{ $reltype_direct_idx->{$type}{'content'} }, $arc;
	}

    }

#    warn Dumper $arcs;
    return bless $arcs, $class;
}

sub init_rev
{
    # Look up all rev arcs for this topic
    #
    my( $class, $t ) = @_;

#    warn "find revs for $t->{t}\n";

    my $arcs =
    {
	t => $t,
	dir => 'rev',
    };

    # Set up indexes
    #
    my $topic_idx = $arcs->{'topic_idx'} ||= {};
    my $reltype_idx = $arcs->{'reltype_idx'} ||= {};
    my $reltype_direct_idx = $arcs->{'reltype_direct_idx'} ||= {};


    my $revs = $Para::dbix->select_list("from rel where rel=? and rel_active is true
                            and rel_strength >= ?", $t->id, TRUE_MIN);
    foreach my $rev ( @$revs )
    {
	defined $rev->{'rel_type'} or die "rel_type undef: ".Dumper( $rev );
	my $type = $rev->{'rel_type'};
	my $revt = $rev->{'rev'};
	my $arc =  Para::Arc->new($rev);

	## Insert context info in arc object
	$arc->{'dir'} = 'rev';

	## Full idx
	push @{ $arcs->{'content'} }, $arc;

	## Topic idx
	$topic_idx->{$revt} ||= $class->new({
	    dir    => 'rev',
	    select => 'topic',
	    topic  => $rev,
	});
	push @{ $topic_idx->{$revt}{'content'} }, $arc;

	## Reltype idx
	$reltype_idx->{$type} ||= $class->new({
	    dir     => 'rev',
	    select  => 'reltype',
	    reltype => $type,
	});
	push @{ $reltype_idx->{$type}{'content'} }, $arc;

	## Reltype direct idx
	unless( $rev->{'rel_indirect'} )
	{
	    $reltype_direct_idx->{$type} ||= $class->new({
		dir     => 'rev',
		select  =>'reltype',
		reltype => $type,
	    });
	    push @{ $reltype_direct_idx->{$type}{'content'} }, $arc;
	}

      }

    return bless $arcs, $class;
}

sub find
{
    my( $arcs, $props ) = @_;

    if( my $tid = $props->{'topic'} )
    {
	$tid = $tid->id if ref $tid eq 'Para::Topic';
	return $arcs->{'topic_idx'}{$tid} || $arcs->new;
    }
    elsif(defined( my $type = $props->{'type'} ))
    {
	if( $props->{'direct'} )
	{
	    return $arcs->{'reltype_direct_idx'}{$type} || $arcs->new;
	}
	else
	{
	    return $arcs->{'reltype_idx'}{$type} || $arcs->new;
	}
    }
    elsif( my @keys = keys %$props )
    {
	die "Keys @keys not implemented";
    }
    else
    {
	return $arcs;
    }
}


### Object methods

sub type
{
    # Just return first match or undef
    #
    my( $arcs, $type ) = @_;

    foreach my $arc ( @{$arcs->{'content'}} )
    {
	if( $arc->{'rel_type'} == $type )
	{
	    return $arc;
	}
    }
    return undef;
}

sub types
{
    # List of types represented among direct active rels
    #
    my( $arcs ) = @_;

    my @types;
    if( $arcs->{'reltype_direct_idx'} )
    {
	push @types, map Para::Arctype->new($_), sort keys %{$arcs->{'reltype_direct_idx'}};
    }
    else
    {
	die "not implemented";
    }
    return \@types;
}

sub topics
{
    my( $arcs ) = @_;

    unless( $arcs->{'topics'} )
    {
	my $dir = $arcs->{'dir'};
	my @t;
	foreach my $arc ( @{$arcs->{'content'}} )
	{
	    push @t, Para::Topic->new( $arc->{$dir} );
	}
	$arcs->{'topics'} = \@t;
    }
    return $arcs->{'topics'};
}

sub arcs
{
    my( $arcs ) = @_;
    return $arcs->{'content'}  || [];
}

sub size
{
    return scalar @{$_[0]->{'content'}} || 0;
}

sub dir
{
    return shift->{'dir'};
}

sub rdir
{
    my( $arcs ) = @_;
    my $dir = $arcs->{'dir'};
    if( $dir eq 'rev' )
    {
	return 'rel';
    }
    elsif( $dir eq 'rel' )
    {
	return 'rev';
    }
    else
    {
	die "Object $arcs has invalid dir: $dir\n";
    }
}

sub topic
{
    return $_[0]->{'topic'};
}


use constant NORMSIZE => 7;

sub by_deviation
{
    return( abs( ( scalar keys %{ $b->{'content'} } ) - NORMSIZE/2 )
	    <=>
	    abs( ( scalar keys %{ $a->{'content'} } ) - NORMSIZE/2 )
	    );
}

sub presentation
{
    my( $arcs ) = @_;


    ### TODO: Include "Övrigt" and insert topics without group there
    # (also remove small groups and move their topics to Övrigt)
    # Also, support large groups

    ### Returns hashref:
    #
    #	size    => the number of arcs to present
    #	groups  => ref to orderd list of $group hashes
    #	arcs    => the $arcs object
    #	title   => the reltype name for the direction
    #
    # Each $group hash has:
    #
    #   title   => Title of the group
    #   content => listref to $xarc orderd by name of related node
    #
    # Each $xarc hash has:
    #
    #   arc     => the actual arc object in the group
    #   topic   => the related node in the arc

    my $topics = $arcs->topics;
    my $dir = $arcs->dir;
    my $total_size = scalar @$topics;
    my $groups_number; # The number of groups left for presentation

    unless( defined  $arcs->{'reltype'} )
    {
	# No arcs in this object
	return
	{
	 size => 0,
	 groups => [],
	 arcs => [],
	 title => 'Empty',
	};
    }

    my $type_rec = $Para::dbix->select_record("from reltype where reltype=?", $arcs->{'reltype'});
    my $title = $type_rec->{$dir."_name"}; # Reltype name in the selected direction

    my @group_list = ();

    if( $total_size < NORMSIZE * 2 )
    {
	my @content;
	foreach my $basearc ( @{$arcs->arcs} )
	{
	    $basearc or die Dumper $arcs->arcs;
	    push @content,
	    {
		arc => $basearc,
		topic => $basearc->node($dir),
	    };
	}
	my $group =
	{
	    title => '',
	    content => [ sort {$a->{'topic'}->desig cmp $b->{'topic'}->desig} @content ],
	};
	push @group_list, $group;
    }
    else
    {
	my %groups;
	my %groupsize;
	my %placements;
	my $other;
	my %temp_others;

	### %groups holds data about the related nodes, hashed by the
	# group:
	#
	# $groups{ $group_topic_id } = $group_a;
	#
	# $group_a =
	# {
	#   content => ref to hash with $related_topic_id => $xarc,
	#   topic   => $group_topic_object,
	# };
	#
	# $xarc is the same as in the return data structure

	### %groupsize is not curently used

	### %placements lets you look up the grops each related node
	# belongs to:
	#
	# $placements{ $t_id }{ $group_topic_id } =
	#   $group_topic_object;

	### %other is the rest group for topics not shown in any other
	# group
	#
	# $other = $group_a;

	if( debug )
	{
	    warn "\n";
	    warn "Relation: $title\n";
	    warn "Reltype $arcs->{reltype}\n";
	    warn "  Size: $total_size arcs to present\n";
	}

	# These will not be used for grouping
	#
	my @taboo = (2, 3, 4, 6, 7, 8, 35601, 10, 11, 12, 3719, );

	# We will group on topics related to through these reltypes
	#
	foreach my $type ( 1, 2, 3 )
	{
	    # Foreach arc to be presented
	    #
	    foreach my $basearc ( @{$arcs->arcs} )
	    {
		debug(1,"basearc ".$basearc->desig);

		# The related node to be presented (may be entry)
		#
		my $t = $basearc->node($dir);
		unless( $t )
		{
		    die sprintf("Basearc %s has no node in dir %s", $basearc->id, $dir);
		}

		##
		#
		$placements{$t->id} ||= {};

		# The related topic. Same as $t unless $t are an entry
		#
		my $topic = (($t->entry ? $t->topic : $t ) || $t );

		# Does the related topic have a relation of the
		# reltype for this iteration?  This will be the
		# relations of the related topic:
		#
		if( my $rels = $topic->rel({type => $type}) )
		{
		    my $count = $rels->size;
		    debug(1,"\tHas $count arcs");

		    # Iterate through the related topic relations
		    #
		    foreach my $arc (@{ $rels->arcs })
		    {
			# The node of the relation from the related
			# topic. This will be one of the topics we may
			# group the arcs to be presented
			#
			my $relt = $arc->node('rel');
			unless( $relt )
			{
			    die Dumper $rels->arcs;
#			    die sprintf("Arc %s has no node in dir %s", $arc->id, $arcs->rdir);
			}
			my $reltid = $relt->id;

			# Skip grouping topic if its in taboo list
			#
			next if grep $reltid == $_, @taboo;

			debug(1,"\t\tInserting ".$relt->desig);
			$groups{$reltid}{'content'}{$t->id}{'arc'} = $basearc;
			$groups{$reltid}{'content'}{$t->id}{'topic'} = $t;
			$groups{$reltid}{'topic'} ||= $relt;
			$placements{$t->id}{$reltid} = $relt;
		    }
		    debug(1,"\tdone");
		}
		else
		{
		    debug(1,"\tNo arcs of type $type");
		}
		debug(1,"more basearcs?");
	    }
	    debug(1,"Type $type done");
	}

	debug(1,"\nChecking topics\n\n");

	# Go through the groups, starting with the worst
	# groups. Groups with to many or to few members.
	#
	# By eliminating the worst choices, we hope to have the best
	# groups left.
	#
	foreach my $group_a ( sort by_deviation values %groups )
	{
	    my $super = $group_a->{'topic'};

	    debug(1,"Check group ".$super->desig);

	    # Mark as exclusive if this group has members not present
	    # in any other group.  In that case, we can't get rid of
	    # it, whithout using a group 'övrigt'.  But that descision
	    # comes later.
	    #
	    $group_a->{'exclusive'} = 0;

	    # Go through the related topics for this group
	    #
	    foreach my $tid ( keys %{$group_a->{'content'}} )
	    {
		# Belongs this topic only to one group?
		#
		if( (scalar keys %{$placements{$tid}}) == 1 )
		{
		    if( debug )
		    {
			my $t = Para::Topic->new($tid);
			my $title = $t->desig;
			warn "\t$title has no other belongings\n";
			foreach my $relt ( values %{$placements{$tid}} )
			{
			    warn "\t\t".$relt->desig."\n";
			}
		    }

		    # If so, mark group as exclusive
		    #
		    $group_a->{'exclusive'} ++;
		    last;
		}
	    }

	    # Remove group unless it's exclusive. This will continue
	    # until only the best exclusive groups are left, since the
	    # better groups will become exclusive then the worse
	    # groups are removed.
	    #
	    # Keep the rest of the least devient groups
	    #
	    # Also remove groups that contaions all related topics
	    #
	    $groups_number = scalar(keys %groups);
	    debug(1,"\tNow $groups_number groups");
	    next if $groups_number < NORMSIZE;

	    my $group_size = scalar(keys %{$group_a->{'content'}});
	    if( $group_a->{'exclusive'} and $group_size == $total_size )
	    {
		debug(1,"\tremoved because all inclusive");
		foreach my $tid ( keys %{$group_a->{'content'}} )
		{
		    $temp_others{ $tid } = $group_a->{'content'}{ $tid };
		    delete $placements{$tid}{$super->id};
		}
		delete $groups{$super->id};
	    }

	    if( not $group_a->{'exclusive'} )
	    {
		debug(1,"\tremoved");
		foreach my $tid ( keys %{$group_a->{'content'}} )
		{
		    delete $placements{$tid}{$super->id};
		}
		delete $groups{$super->id};
	    }
	}


	# Create a group others by removing the largest groups and see
	# if it shrunk
	#
	my %points; # points for each group
	foreach my $group_a ( values %groups )
	{
	    my $size = scalar keys %{$group_a->{'content'}};

	    my $count = 0;
	    foreach my $tid ( keys %{$group_a->{'content'}} )
	    {
		$count++ if scalar(keys %{$placements{$tid}}) > 1;
	    }

	    # The higher the points, the better to make to %other
	    $points{ $group_a->{'topic'}->id } = $size - $count;
	}
	my @best_other = sort { $points{ $b } <=> $points{ $a } } keys %points;
	foreach my $group_id ( @best_other )
	{
	    my $gname = Para::Topic->new( $group_id )->desig;
	    debug(1,"group $gname has $points{ $group_id } points");
	    if( $points{ $group_id } > NORMSIZE*2 )
	    {
		$other = {};
		if( debug )
		{
		    warn "    Moving topics from group $gname to others\n";
		}

		# Clean out the group
		foreach my $tid ( keys %{$groups{ $group_id }{'content'}} )
		{
		    if( scalar(keys %{$placements{$tid}}) == 1 )
		    {
			$other->{ $tid } =
			  $groups{ $group_id }{'content'}{ $tid };
		    }
		    delete $placements{$tid}{$group_id};
		    $placements{$tid}{'other'} = $other;
		}
		delete $groups{$group_id};
	    }
	}


	## Remove small groups
	#
	foreach my $group_a ( values %groups )
	{
	    debug(1,"Check group ".$group_a->{'topic'}->desig);
	    if( scalar(keys %{$group_a->{'content'}}) < NORMSIZE/2 )
	    {
		debug(1,"\tremoved because too small");
		foreach my $tid ( keys %{$group_a->{'content'}} )
		{
		    $temp_others{ $tid } = $group_a->{'content'}{ $tid };
		    delete $placements{$tid}{$group_a->{'topic'}->id};
		}
		delete $groups{$group_a->{'topic'}->id};

	    }
	}

	# Reinsert from %temp_others to others
	#
	foreach my $tid ( keys %temp_others )
	{
	    next if scalar(keys %{$placements{$tid}}) > 0;
	    $other->{ $tid } = $temp_others{ $tid };
	    $placements{$tid}{'other'} = $other;
	}

	## Remove all groups that are wholy contained in a larger group
	#
      CHECK:
	foreach my $group_a ( values %groups )
	{
	    debug(1,"Check group ".$group_a->{'topic'}->desig);
	    foreach my $tid ( keys %{$group_a->{'content'}} )
	    {
		if( scalar( keys %{$placements{$tid}} ) == 1 )
		{
		    if( debug )
		    {
			my $title = Para::Topic->new($tid)->desig;
			warn "\t$title has no other place\n";
		    }
		    next CHECK;
		}

	    }

	    debug(1,"\tremoved");
	    foreach my $tid ( keys %{$group_a->{'content'}} )
	    {
		delete $placements{$tid}{$group_a->{'topic'}->id};
	    }
	    delete $groups{$group_a->{'topic'}->id};
	}


	# Do show header for just one group
	my $no_headers = 0;
	$groups_number = scalar(keys %groups);
	$groups_number ++ if $other;
	if( $groups_number == 1 )
	{
	    $no_headers = 1;
	}

	# Build the list of groups to return. sort content on topic
	# desig.
	#
	my $link_cnt;
	my $group_cnt;
	foreach my $super_id ( keys %groups )
	{
	    my $super = Para::Topic->new( $super_id );
	    my $group = {};
	    $group->{title} = $super->title unless $no_headers;
	    my @sorted = sort( {$a->{'topic'}->desig cmp $b->{'topic'}->desig}
			       values %{$groups{$super_id}{'content'}}
			       );
	    $group->{content} = \@sorted;
	    push @group_list, $group;
	    $link_cnt += @sorted;
	    $group_cnt ++;
	}

	# Add group %other
	#
	if( $other )
	{
	    my $group = {};
	    $group->{title} = 'Övriga' unless $no_headers;
	    my @sorted = sort( {$a->{'topic'}->desig cmp $b->{'topic'}->desig}
			       values %{$other}
			     );
	    $group->{content} = \@sorted;
	    push @group_list, $group;
	    $link_cnt += @sorted;
	    $group_cnt ++;
	}

	debug(1,"Inserted $link_cnt links over $group_cnt groups");
    }

    my $result =
    {
	size => $total_size,
	groups => [sort {$a->{'title'} cmp $b->{'title'}} @group_list ],
	arcs => $arcs,
	title => $title,
    };

    return $result;
}

1;
