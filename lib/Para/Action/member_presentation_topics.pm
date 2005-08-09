#  $Id$  -*-perl-*-
package Para::Action::member_presentation_topics;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se find topics from presentation
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
use locale;
use Data::Dumper;
use POSIX qw(locale_h);

use Para::Frame::Utils qw( throw debug );

use Para::Member;
use Para::Widget;

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;
    my $q = $req->q;

    my $mid = $q->param('mid') || $u->id;
    my $m = Para::Member->get( $mid );

    setlocale(LC_ALL, "sv_SE");

    Para::Widget::new_entry();

    # Find key words from text.
    # Code based on Para::Widget::insert_autolinks()

    my $text = $m->presentation;


#    warn "Using presentation: $text\n";
    my $topics = {};
    for( my $size=$#$Para::link_db; $size >= 0; $size -- )
    {
#	warn "Size $size\n";
	$text =~ /(\W*)/gc;
	while( $text =~ /(\w+)(\W*)/gc ) #iterate failsafe
	{
#	    warn " On $1\n";
	    if( my $try = $Para::link_db->[$size]{lc($1)} )
	    {
		my $match = $1;
		my $middle = $2 || "";
#		warn "  Checking $match\n";
		my $pos = pos($text);
		if( $size and $text =~ /((?:\w+(?:\W+|$)){$size})/gc )
		{
		    my $rest = $1;
		    $rest =~ s/(\W+)$//;
		    my $looking = $match . $middle . $rest;
#		    warn "    looking for $looking\n";
		    if( my $rec = $try->{lc($looking)} )
		    {
#			warn "      Matched $looking!\n";
#			warn "        Noted $rec->{'alias'}\n";
			$topics->{$rec->{'tid'}} = $rec->{'alias'};
		    }
		    else
		    {
			pos($text) = $pos;
		    }
		}
		elsif( not $size )
		{
#		    warn "      Matched $match!\n";
		    my $rec = $try->{lc($match)};
#		    warn "        Noted $rec->{'alias'}\n";
		    $topics->{$rec->{'tid'}} = $rec->{'alias'};
		}
		else
		{
		    pos($text) = $pos;
		}
	    }
	}
	pos($text) = 0;

	# Remove matched words from text
	foreach my $word ( values %$topics )
	{
	    $text =~ s/$word//gi;
	}
    }

    my $interests = join "\n", values %$topics;
    $q->param('_interests', $interests);

    return "Hämtade intressen från presentationen\n";
}

1;
#http://test.paranormal.se:81/member/db/person/interest/enter_list.tt?run=member_presentation_topics
