package TestApp::Controller::Root;

use strict;
use warnings;
use base 'Catalyst::Controller::POD';

__PACKAGE__->config->{namespace} = '';

sub test : Local {
    my ( $self, $c ) = @_;

    $c->response->body( "here I am" );
}


1;
