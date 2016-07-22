package Para::Action::do_bgjob;

use strict;
use Sys::CpuLoad;

sub handler
{
	my $last_time = $Para::Frame::BGJOBDATE ||= time;
	my $delta = time - $last_time;
	my $sysload = (Sys::CpuLoad::load)[1];
	my $req = $Para::Frame::REQ;
	Para::Frame::add_background_jobs($delta, $sysload);
	Para::Frame::switch_req( $req );
	return "BGjobs done";
}

1;
