#  $Id$  -*-perl-*-
package Para::Action::topic_search_published;

use strict;
use Data::Dumper;
use CGI;

use Para::Frame::Utils qw( throw catch debug );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;
    my $result = $req->result;

    my $talias = $q->param('talias');

    debug("Searching for '$talias'") if $talias;
    # In some cases will we have to de-escape the string
    if( $talias and $talias =~ /%[0-9A-F][0-9A-F]/ )
    {
	$talias = CGI::unescape($talias);
	debug "  Now searching for '$talias'";
    }

    my $t;
    my $res = eval
    {
	if( my( @tids ) = $q->param('tid') )
	{
	    if( @tids > 1 )
	    {
		my $topics = [];
		foreach my $tid ( @tids )
		{
		    push @$topics, Para::Topic->get_by_id( $tid );
		}

		$result->{'info'}{'alternatives'}{'list'} = $topics;
		throw 'alternatives', "Välj en av dessa";
	    }
	    else
	    {
		$t = Para::Topic->get_by_id($tids[0] );
		$talias = $t->desig;
	    }
	}
	elsif( my $constraint = $q->param('constraint') )
	{
	    my $target_tid = $q->param('constraint_target');
	    my $target = Para::Topic->get_by_id( $target_tid );

	    $constraint =~ /^(re.)_(\w+)$/;
	    my $dir = $1;
	    my $type_id = $2;

	    my $topics_in = Para::Topic->find($talias);
	    my $topics_out = [];
	    foreach $t (@$topics_in)
	    {
		debug "  Checking ".$t->desig;
		if( $dir eq 'rev' ) # Check in other dir
		{
		    if( $type_id eq 'ts' )
		    {
			next unless @{$t->ts_list};
		    }
		    else
		    {
			next unless $t->has_rel($type_id, $target);
		    }
		}
		else
		{
		    if( $type_id eq 'ts' )
		    {
			next unless @{$t->ts_revlist};
		    }
		    else
		    {
			next unless $t->has_rev($type_id, $target);
		    }
		}
		push @$topics_out, $t;
	    }

	    if( @$topics_out > 1 )
	    {
		$result->{'info'}{'alternatives'}{'list'} = $topics_out;
		throw('alternatives', "Välj ett av dessa alternativ för ämnet '$talias'");
	    }
	    elsif( @$topics_out < 1 )
	    {
		# Make a substring search

		throw('notfound', "Vi har ingen '$talias' under ämnet '".lc($target->title)."'.");
	    }
	    else
	    {
		$t = $topics_out->[0];
	    }
	}
	else
	{
	    $t = Para::Topic->find_one($talias);
	}

	my $path = $t->file or
	    throw('notfound', "Detta uppslagsord finns i databasen, men är hemligt.");
	my $filename = $req->uri2file( $path );
	debug "Trying $filename";
	if( -r $filename ) # Realy existing?
	{
	    $req->redirect($path);
	    my $title = $t->title;
	    return "Found $title";
	}
	else
	{
	    $result->{'info'}{'notfound'}{'uri'} = $path;
	    $result->{'info'}{'notfound'}{'tid'} = $t->id;
	    $result->{'info'}{'notfound'}{'name'} = $talias;

	    # Try publish right now
	    $t->publish;
	    my $filename = $req->uri2file( $path );
	    debug "Trying $filename again";
	    if( -r $filename ) # Realy existing?
	    {
		$req->redirect($path);
		my $title = $t->title;
		return "Found $title";
	    }
	    else
	    {
		throw('notfound', "Detta uppslagsord finns i databasen, men är hemligt.");
	    }
	}
	return 0;
    };
    return $res if $res; # result of eval

    if( my $err = catch(['notfound','alternatives'])  )
    {
	# Do not catch constraint search
	die $@ if $q->param('constraint');

	if( $err->type eq 'notfound' )
	{
	    my $query = $q->escapeHTML($talias);
	    $req->redirect("/cgi-bin/htsearch?config=htdig&words=$query");
	    return "$talias Not found";
	}
	elsif( $err->type eq 'alternatives' )
	{
	    return $err->info;
	}
    }

    if( $t and $t->member )
    {
	my $m = $t->member;
	if( $m->present_contact_public < 1 )
	{
	    my $query = $q->escapeHTML($talias);
	    $req->redirect("/cgi-bin/htsearch?config=htdig&words=$query");
	    return "$talias Not found";
	}
	else
	{
	    throw('notfound', "Hittade $talias, men medlemmen önskar vara anonym.");
	}
    }
    

    throw('notfound', "Hittade $talias, men det uppslagsordet är hemligt.");
}

1;
