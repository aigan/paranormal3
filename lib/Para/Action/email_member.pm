#  $Id$  -*-perl-*-
package Para::Action::email_member;

use strict;

use Para::Frame::Utils qw( throw );

use Para::Member;
use Para::Widget;

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;
    my $q = $req->q;

    my $mid = $q->param('mid') or
	throw('validation', "mid param missing");

    my $from = $q->param('from') || 'psi_cgi@paranormal.se';
    my $subject = $q->param('subject') || '<inget ämne>';

    my $m = Para::Member->get_by_id( $mid );

    my $fork = Para::Email->send_in_fork({
	subject => $subject,
	m => $m,
	template => 'custom.tt',
	from => $from,
	cnt => 1,
    });

    $fork->yield;
    return "Aborted" if $fork->failed;
    return sprintf "E-post har skickats till %s.", $m->desig;
}

1;
