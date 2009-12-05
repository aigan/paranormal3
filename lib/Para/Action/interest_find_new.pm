# -*-cperl-*-
package Para::Action::interest_find_new;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw uri debug trim );

use Para::Member;
use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    my $mid = $q->param('mid') or throw('incomplete', "mid param missing\n");

    if( $u->level < 40 and $u->id != $mid )
    {
	throw('denied', "Du har inte access för att ändra någon annans intressen.");
    }

    my $m = Para::Member->get($mid);

    # 1. For each row
    #    1. Find topic eliminate duplicates
    #    2. Add interest at level 1
    #    3. Add not found topics to new-list
    # 2. If new-list
    #    1. Set title to fitst value
    #    2. store the rest of the new-list in session new_interests
    #    3. Add enter_list to route
    #    4. Redirect to create new topic

    my $news = {};

    # Get from session
    #
    my $news = $req->s->{'new_interests'} ||= {};

    # Add rom query
    #
    foreach my $name ( split /\r?\n/, lc $q->param('_interests') )
    {
	trim(\$name);
	next unless length $name;
	$news->{$name} ++;
    }

    $req->result->message(Para::Frame::Widget::inflect scalar( keys %$news),
			  "Inga fler nya intressen att undersöka",
			  "Tittar igenom ett nytt intresse",
			  "Tittar igenom %d nya intressen" );

    foreach my $line ( keys %$news )
    {
	my $alts = Para::Topic->find_by_alias($line, {status_min=>2});
	foreach my $t ( @$alts )
	{
	    $m->interests->getset( $t ); # Mark interest
	}

	if( @$alts )
	{
	    delete $news->{$line}; # Taken care of
	}
	else # Could the line be in invalid format?
	{
	    # Should rather be done once instead...
	    #
	    if( $line =~ /,/ )
	    {
		delete $news->{$line}; # Remove from session
		throw('validation', "Angående: $line\nEtt ämne per rad.\nInga kommatecken");
	    }
	    if( $line =~ /\./ )
	    {
		delete $news->{$line}; # Remove from session
		throw('validation', "Angående: $line\nAnvänd inte förkortingar.\nInga punkter");
	    }
	    if( $line =~ tr/ // > 2 )
	    {
		delete $news->{$line}; # Remove from session
		throw('validation', "Angående: $line\nAnge bara ämnesnamn som man kan\ntänkas slå upp i en uppslagsbok.");
	    }
	}
    }

    $q->delete('_interests');

    if( my @news = keys %$news )
    {
	$req->s->route->plan_next( uri "/member/db/person/interest/specify_list.tt",
				   {
				       run => "interest_find_new",
				       mid => $mid,
				   });

	$req->result->message(Para::Frame::Widget::inflect scalar(@news), "1 intresse är okänt", "%d intressen är okända" );

	my $alias = pop @news;
	$q->param('_name', ucfirst $alias);
	delete $news->{$alias};

	$req->set_page('/member/db/topic/create/maby.tt');
    }
    else
    {
	delete $req->s->{'new_interests'};
    }

    return "";
}

1;
