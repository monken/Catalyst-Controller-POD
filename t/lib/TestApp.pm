package TestApp;

use strict;
use warnings;

use Catalyst::Runtime '5.70';

use parent qw/Catalyst/;

our $VERSION = '0.01';
__PACKAGE__->config( name => 'TestApp' ,
"Controller::Root" => {}
);
__PACKAGE__->setup(qw/Static::Simple/);


1;
