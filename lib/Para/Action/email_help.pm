#  $Id$  -*-perl-*-
package Para::Action::email_help;

use strict;

use Para::Frame::Utils qw( throw );

use Para::Member;
use Para::Widget;

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;
    my $q = $req->q;

    my $from = $q->param('from') || 'spam@paranormal.se';
    my $subject = $q->param('subject')
	or throw('validation', "Ange en tydlig rubrik till brevet");

    my $fork = Para::Email->send_in_fork({
	subject => $subject,
	to => 'helpers@paranormal.se',
	template => 'custom.tt',
	from => $from,
    });

    $fork->yield;
    return "Aborted" if $fork->failed;
    return sprintf "E-post har skickats till hjälparna";
}

1;
