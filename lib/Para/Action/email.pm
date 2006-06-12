#  $Id$  -*-perl-*-
package Para::Action::email;

use strict;

use Para::Frame::Utils qw( throw in );

use Para::Member;
use Para::Widget;

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;
    my $q = $req->q;

    my $to_str = $q->param('to')
	or throw('validation', "Mottagare för brevet saknas");

    my $to = Para::Email::Address->parse($to_str);
    $to_str = $to->address;

    # Valid reciepients:
    #
    my @valid = qw( red@paranormal.se
		    jonas@paranormal.se
		    help@paranormal.se
		    info@paranormal.se
		    memadmin@paranormal.se
		    );
    unless( in $to_str , @valid )
    {
	throw('validation', "$to_str is not one of the valid reciepients");
    }



    my $from = $q->param('from') || 'psi_cgi@paranormal.se';
    my $subject = $q->param('subject')
	or throw('validation', "Ange en tydlig rubrik till brevet");

    $q->param('body')
	or throw('validation', "Men du har ju inte skrivit något");


    my $fork = Para::Email->send_in_fork({
	subject => $subject,
	to => $to,
	template => 'custom.tt',
	from => $from,
    });

    $fork->yield;
    return "Aborted" if $fork->failed;

    my $to_desig = $to->desig;
    return "E-post har skickats till $to_desig";
}

1;
