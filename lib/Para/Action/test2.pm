package Para::Action::test2;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

sub handler
{
	my( $req ) = @_;
	my $q = $req->q;

	my $fork = $req->create_fork;

	if ( $fork->in_child )
	{
		warn "*** In fork\n";

#	sleep 10;
		die "got error";

		$fork->return("Message 2 from the child");
		die "How did we get here?!?\n";
	}
	warn "*** Outside fork\n";

	warn "** Before yield\n";
	$fork->yield;
	warn "** After yield\n";

	my $result = $fork->result;
	my $message = $result->message;

	my $status = $fork->status;

	$req->result->message( $message );
	my $pid = $fork->pid;
	return "Processed the result of the child $pid with status $status";
}

1;
