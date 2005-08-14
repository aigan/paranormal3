#  $Id$  -*-perl-*-
package Para::Action::email_combined_list;

use strict;

use Para::Frame::Utils qw( throw );

use Para::Member;
use Para::Widget;

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;
    my $q = $req->q;

    if( $u->level < 7 )
    {
	throw('denied', "Du måste vara minst nivå 7 för att skicka epost till en lista");
    }

    my $list = Para::Widget::select_persons();
    my $subject = $q->param('subject');

    my $from = $u->sys_email->format;

    my $note = "";

    foreach my $rec ( @$list )
    {
	my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	my $fork = Para::Email->send_in_fork({
	    subject => $subject,
	    m => $m,
	    template => 'custom.tt',
	    from => $from,
	});
    }

    return "Skickar breveven i fork...";
}

1;
