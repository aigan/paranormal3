# -*-cperl-*-
package Para::Constants;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Constants class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use warnings;
use base 'Exporter';
use vars qw( @EXPORT_OK %EXPORT_TAGS @ALL $AUTOLOAD $INITIALIZED %Constants @Constants_keys );

#use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );



BEGIN
{
    debug "Setting up constants";

    my @constants =
	(

	 S_DENIED   => 0,
	 S_REPLACED => 1,
	 S_PROPOSED => 2,
	 S_PENDING  => 3,
	 S_NORMAL   => 4,
	 S_FINAL    => 5,
	 
	 C_KILL     => -2,
	 C_BAN      => -1,
	 C_NORMAL   =>  0,
	 C_VOICE    =>  2,
	 C_HALFOP   =>  3,
	 C_OP       =>  4,
	 C_OPER     =>  5,
	 
	 TRUE_MIN   => 30,
	 TRUE_NORM  => 80,
	 
	 T_LOST_ENTRY        => 137624,
	 T_MEDIA             => 4463,
	 T_PRENUMERATION     => 422154,
	 T_PARANORMAL_SWEDEN => 144554,
	 T_PAYNOVA           => 422381,
	 T_PERSON            => 2140,
	 T_ENGLISH           => 396598,
	 T_GUESTBOOK         => 626847,

	 DB_ALIAS    => '/var/local/paranormal/alias.db',
	 DB_PASSWD   => '/var/local/paranormal/passwd.db',
	 DB_ONLINE   => '/var/local/paranormal/online.db',
	 
	 HA_CREATE   => 1,
	 HA_UPDATE   => 2,
	 HA_DELETE   => 3,
	 
	 HS_CREATED  => 1,
	 
	 MONTH_LENGTH => 30.417,
	 
	 M_VIP => 50,
	 );

    # Better way to go through the list?
    while( my $key = shift @constants )
    {
	my $val = shift @constants;
	$Constants{ $key } = $val;
	push @Constants_keys, $key;
    }


    @ALL = map "\$C_$_", keys %Constants;
#    debug "Constant list: @ALL";
}

@EXPORT_OK   = ( @ALL );
%EXPORT_TAGS = ( 'all' => [@ALL] );

sub init ()
{
    debug "Initiating constants";

    no strict 'refs';
    foreach my $key ( @Constants_keys )
    {
	debug 2, "  Set up constant $key";
	${'C_'.$key} = $Constants{$key};
    }


    $Para::mtitle =
    {
	-2 => ['zombie','zombie'],
	-1 => ['saknade','saknade'],
	0  => ['',''],
	1  => ['nykomling','nykomling'],
	11  => ['lärling','lärling'],
	40 => ['mäster','mäster'],
	41 => ['livbringare','livbringare'],
	42 => ['','skapare'],
    };

    for( 2..4 ){ $Para::mtitle->{$_} = ['novis','novis'] }
    for( 5..10 ){ $Para::mtitle->{$_} = ['','medborgare'] }
    for( 12..39 ){ $Para::mtitle->{$_} = ['gesäll','gesäll'] }

}

sub new ()
{
    return bless {};
}


AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
    no strict 'refs';
    return ${"C_$AUTOLOAD"};
}


sub on_reload
{
    Para::Frame::Reload->modules_importing_from_us;
}

1;
