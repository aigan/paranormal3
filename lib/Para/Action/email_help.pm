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

    my $from = $q->param('from')
	or throw('validation', "Du beh�ver ange en fr�n-adress");
    my $subject = $q->param('subject') || '<inget �mne>';

    my $fork = Para::Email->send_in_fork({
	subject => $subject,
	to => 'helpers@paranormal.se',
	template => 'custom.tt',
	from => $from,
    });

    $fork->yield;
    return "Aborted" if $fork->failed;
    return sprintf "E-post har skickats till hj�lparna";
}

1;
