package Para::Action::test;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

sub handler
{
    my( $req ) = @_;
    my $q = $req->q;

    my $fork = $req->create_fork;
    if( $fork->in_child )
    {
	warn "*** In fork\n";
	sleep 10;
	$fork->on_return('process_my_data');
	$fork->return("Message from the child");
	die "How did we get here?!?\n";
    }
    warn "*** Outside fork\n";

    return "test parent\n";
}

sub process_my_data
{
    my( $result, @args ) = @_;

    my $pid = $result->pid;

    return "Processed the result of the child $pid";
}

1;
