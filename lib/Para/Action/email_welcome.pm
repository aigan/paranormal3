package Para::Action::email_welcome;

use strict;

use Para::Frame::Utils qw( throw );

use Para::Email;
use Para::Member;

sub handler
{
    my( $req ) = @_;
    my $q = $req->q;
    my $mid = $q->param('mid');
    my $m = Para::Member->get( $mid );

    my $e = Para::Email->new;

    $e->set({
	subject => "Välkommen till Paranormal.se",
	m => $m,
	template => 'welcome.tt',
	from => "devel\@paranormal.se",
    });

    $e->send or throw('email', $e->error_msg);

    return "E-post har nu skickats till $m->{'sys_email'} med ditt lösenord.\n";
}

1;
