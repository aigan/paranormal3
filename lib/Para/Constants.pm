#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use base 'Exporter';
use vars qw( @EXPORT_OK %EXPORT_TAGS );

use constant S_DENIED   => 0;
use constant S_REPLACED => 1;
use constant S_PROPOSED => 2;
use constant S_PENDING  => 3;
use constant S_NORMAL   => 4;
use constant S_FINAL    => 5;

use constant C_KILL     => -2;
use constant C_BAN      => -1;
use constant C_NORMAL   =>  0;
use constant C_VOICE    =>  2;
use constant C_HALFOP   =>  3;
use constant C_OP       =>  4;
use constant C_OPER     =>  5;

use constant TRUE_MIN   => 30;
use constant TRUE_NORM  => 80;

use constant T_LOST_ENTRY        => 137624;
use constant T_MEDIA             => 4463;
use constant T_PRENUMERATION     => 422154;
use constant T_PARANORMAL_SWEDEN => 144554;
use constant T_PAYNOVA           => 422381;
use constant T_PERSON            => 2140;
use constant T_ENGLISH           => 396598;

use constant DB_ALIAS    => '/var/local/paranormal.test/alias.db';
use constant DB_PASSWD   => '/var/local/paranormal.test/passwd.db';
use constant DB_ONLINE   => '/var/local/paranormal.test/online.db';

use constant HA_CREATE   => 1;
use constant HA_UPDATE   => 2;
use constant HA_DELETE   => 3;

use constant HS_CREATED  => 1;

use constant MONTH_LENGTH => 30.417;

use constant M_VIP => 50;


@EXPORT_OK = qw( HA_CREATE HA_UPDATE HA_DELETE HS_CREATED S_DENIED
                 S_REPLACED S_PROPOSED S_PENDING S_NORMAL S_FINAL
                 TRUE_MIN TRUE_NORM T_LOST_ENTRY T_MEDIA T_PERSON
                 DB_ALIAS DB_PASSWD DB_ONLINE MONTH_LENGTH
                 T_PRENUMERATION T_PARANORMAL_SWEDEN T_PAYNOVA
                 T_ENGLISH C_KILL C_BAN C_NORMAL C_VOICE C_HALFOP C_OP
                 C_OPER M_VIP );

%EXPORT_TAGS = ( 'all' => [@EXPORT_OK] );


 Titles:
{
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

sub on_reload
{
    Para::Frame::Reload->modules_importing_from_us;
}

1;
