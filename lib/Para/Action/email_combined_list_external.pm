# -*-cperl-*-
package Para::Action::email_combined_list_external;

use strict;

use Para::Frame::Utils qw( throw debug trim );

use Para::Member;

sub handler
{
	my( $req ) = @_;

	my $u = $Para::Frame::U;
	my $q = $req->q;

	if ( $u->level < 41 )
	{
		throw('denied', "Du måste vara minst nivå 41 för att exportera epost till en lista");
	}

	my $list = Para::Member->search({all=>1});

	debug "List has ".$list->size." elements";

	my $data;

	my $old = Para::Frame::Time->get('1990-01-01');

	while ( my $rec = $list->get_next_nos )
	{
		$Para::Frame::REQ->may_yield unless $list->index % 100;

		my $m = Para::Member->get_by_id( $rec->{'member'} );
		debug 0, sprintf "%5d Gettig member %d", $list->count, $rec->{'member'};

		unless( $m->newsmail )
		{
	    debug "Member ".$m->sysdesig." do not want mail";
	    next;
		}
		my $name = $m->desig;
		unless( $name )
		{
	    debug "Member ".$m->sysdesig." has no name";
	    next;
		}
		$name =~ s/"//g;
		$name =~ s/\s+$//g;
		$name =~ s/^\s+//g;

		my @ma = sort { ($b->working||$old) <=> ($a->working||$old)
											||
											($a->failed||0) <=> ($b->failed||0) } $m->mailaliases;

		my $es = $ma[0]->address;

		$data .= sprintf '"%s" <%s>'."\n", $name, $es;
	}

	$u->session->{'combined_email'} = $data;

	return('Created e-mail to all of list');
}

1;
