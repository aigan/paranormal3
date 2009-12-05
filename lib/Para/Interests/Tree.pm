# -*-cperl-*-
package Para::Interests::Tree;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se member interests tree
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

use strict;
use warnings;

use Data::Dumper;

use Para::Frame::DBIx;

use Para::Topic;

use base qw(Class::Accessor);

# Create accessors
#
Para::Interests::Tree->mk_accessors(qw(tree tree_idx topic_idx intrest_idx m));


sub new
{
    die "Extreme intresting error";

    my( $class, $m, $limit, $delta, $bonus ) = @_;

    my $self = bless
    {
	tid         => 0,
	childs      => {},
	size        => 0,
	tree_idx    => {},
	intrest_idx => {},
	m           => $m,
    }, $class;

#    $self->{tree_idx}{0} = $self;

    $limit ||= 30;
    $delta ||= 0;
    $bonus ||= 0;

    my $intrest_list = $Para::dbix->select_list('from intrest where intrest_member=? and intrest >= 30', $m->{'member'});

    foreach my $intrest ( @$intrest_list )
    {
	my $tid = $intrest->{'intrest_topic'};
	my $topic = Para::Topic->get_by_id( $tid );
	$self->{intrest_idx}{ $tid } = $intrest;
	my $node =
	{
	    tid     => $tid,
	    intrest => $intrest,
	    topic   => $topic,
	    parents => {},
	    childs  => {},
	    size    => 0,
	};
	$self->{tree_idx}{ $tid } = $node;

	foreach my $rtid ( keys %{ $self->{childs} } )
	{
	    my $snodes = $self->is_parent( $rtid, $tid );
	    foreach my $snode ( @$snodes )
	    {
		# First check siblings
		foreach my $sibtid ( keys %{$snode->{childs}} )
		{
		    if( $self->is_child( $sibtid, $tid ) )
		    {
			my $sibnode = $self->{tree_idx}{$sibtid};
			$node->{childs}{$sibtid} = $sibnode;
			$sibnode->{parents}{$tid} = $node;
			
			# Break old link
			delete $snode->{childs}{$sibtid};
			delete $sibnode->{parents}{$rtid};
		    }
		}

		$snode->{childs}{$tid} = $node;
		$node->{parents}{ $snode->{tid} } = $snode;
	    }

	    if( $self->is_child( $rtid, $tid ) )
	    {
		my $snode = $self->{tree_idx}{$rtid};
		$node->{childs}{$rtid} = $snode;
		$snode->{parents}{$tid} = $node;

		# Break old link
		delete $self->{childs}{$rtid};
		delete $snode->{parents}{0};
	    }
	}

	unless( keys %{$node->{parents}} ) # No parents?
	{
	    $self->{childs}{ $tid } = $node;
	    $node->{parents}{0} = $self;
	}
    }

    # Score nodes
    foreach my $tid ( keys %{ $self->{childs} } )
    {
	$self->score_node( $tid );
    }

    # Remove intrests below limit
    $self->limit_tree( 0, $limit, $delta, $bonus );

    return $self;
}

sub score_node
{
    my( $self, $tid ) = @_;

    my $node =  $self->{tree_idx}{$tid};
    my $score = 1;
    foreach my $stid ( keys %{ $node->{childs} } )
    {
	$score += $self->score_node( $stid );
    }

    return $node->{size} = $score;
}

sub limit_tree
{
    my( $self, $tid, $limit, $delta, $bonus ) = @_;

    my $node = $self->{tree_idx}{$tid} || $self;

  FLATTEN:
    {
	foreach my $stid ( keys %{$node->{childs}} )
	{
	    my $intrest = $self->{intrest_idx}{$stid};
	    my $snode = $self->{tree_idx}{$stid};
	    if( $intrest->{intrest} < $limit - $snode->{size}*$bonus )
	    {
		foreach my $sstid ( keys %{$snode->{childs}} )
		{
		    my $ssnode = $self->{tree_idx}{$sstid};
		    $ssnode->{parents}{$tid} = $node;
		    $node->{childs}{$sstid} = $ssnode;

		    delete $ssnode->{parents}{$stid};
		    delete $snode->{childs}{$sstid};
		}

		delete $node->{childs}{$stid};
		delete $snode->{parents}{$tid};

		redo FLATTEN;
	    }
	    else
	    {
		$self->limit_tree( $stid, $limit+$delta, $delta, $bonus );
	    }
	}
    }    
}

sub is_parent
{
    my( $self, $ctid, $tid ) = @_;
    #
    # Is candidated (ctid) a parent of tid?

    my $topic = Para::Topic->get_by_id($tid) or return undef;

    my $rel = $topic->rel({topic=>$ctid});
    if( $rel and ( $rel->type(2) or $rel->type(3) ) )
    {
	my $cnode = $self->{tree_idx}{$ctid};
	my @snodes = ();
	foreach my $stid ( keys %{$cnode->{childs}} )
	{
	    push @snodes, @{ $self->is_parent( $stid, $tid ) };
	}

	if( @snodes )
	{
	    return \@snodes;
	}
	else
	{
	    return [ $cnode ];
	}
    }
    else
    {
	return [];
    }
}

sub is_child
{
    my( $self, $ctid, $tid ) = @_;
    #
    # Is candidated (ctid) a child of tid?

    my $ctopic = Para::Topic->get_by_id($ctid) or return undef;

    my $node = $self->{tree_idx}{$tid};

    my $rel = $ctopic->rel({topic=>$tid});
    if( $rel and ( $rel->type(2) or $rel->type(3) ) )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

1;
