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

    my $list = Para::Widget::select_persons({all=>1});
    my $subject = $q->param('subject');

    my $from = $u->sys_email->format;

    my $e = Para::Email->new({
	subject => $subject,
	template => 'custom.tt',
	from => $from,
	cnt => scalar(@$list),
    });

    $req->add_background_job(\&send_to_list, $e, $list);

    return "Skickar breveven i bakgrunden i fork ...";
}

sub send_to_list
{
    my( $req, $e, $list ) = @_;

    my $fork = $Para::Frame::REQ->create_fork;
    if( $fork->in_child )
    {
	foreach my $rec ( @$list )
	{
	    my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	    $e->send({ m => $m }); # Ignoring errors
	    # ... or throw('email', $e->error_msg);
	    # TODO: Report errors to sending member
	}
	$fork->return('Sent e-mail to all of list');
    }
    return 1;
}

1;
