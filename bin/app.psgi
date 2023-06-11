#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";


# use this block if you don't need middleware, and only have a single target Dancer app to run here
use Interpolation;

Interpolation->to_app;

=begin comment
# use this block if you want to include middleware such as Plack::Middleware::Deflater

use Interpolation;
use Plack::Builder;

builder {
    enable 'Deflater';
    Interpolation->to_app;
}

=end comment

=cut

=begin comment
# use this block if you want to mount several applications on different path

use Interpolation;
use Interpolation_admin;

use Plack::Builder;

builder {
    mount '/'      => Interpolation->to_app;
    mount '/admin'      => Interpolation_admin->to_app;
}

=end comment

=cut

