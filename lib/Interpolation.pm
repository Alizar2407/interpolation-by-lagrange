package Interpolation;
use Dancer2;
use Template;
use GD;
use GD::Graph::lines;
use DBI;
use File::Spec;
use List::Util qw( min max );

our $VERSION = '0.1';

my $formula = undef;
my $graph_path = undef;
my $rows_count = 4;
my @x_values = ();
my @y_values = ();

hook before_template_render => sub {
    my $tokens = shift;
 
    $tokens->{'css_url'}    = request->base . 'css/style.css';
};

get '/' => sub {
    while (scalar @x_values < 4) {
        my $v = scalar @x_values + 1;
        push @x_values, $v;
        push @y_values, $v;
    }
    while (scalar @x_values > 10) {
        pop @x_values;
        pop @y_values;
    }

    template 'body_template.tt', {
        delete_rows_url => uri_for('/del'),
        add_rows_url => uri_for('/add'),
        interpolate_url => uri_for('/interpolate'),

        rows_count => $rows_count,
        x_arr => [@x_values],
        y_arr => [@y_values],

        formula => $formula,
        graph => $graph_path,
    }; 
};

post '/del' => sub {
    if ($rows_count - 1 >= 4){
        $rows_count -= 1;

        pop @x_values;
        pop @y_values;
    }

    redirect '/';
};

post '/add' => sub {
    if ($rows_count + 1 <= 10){
        $rows_count += 1;

        my $v = scalar @x_values + 1;
        push @x_values, $v;
        push @y_values, $v;
    }

    redirect '/';
};

post '/interpolate' => sub {
    my $n = $rows_count - 1;
    @x_values = ();
    @y_values = ();
    for (0..$n){
        my $x = body_parameters->get("x_value$_");
        my $y = body_parameters->get("y_value$_");

        my %params = map { $_ => 1 } @x_values;
        if(exists($params{$x})) {
            $formula = undef;
            $graph_path = undef;
            redirect '/';
            return;
        }
        
        push @x_values, $x;
        push @y_values, $y;
    }
    
    $formula = "";
    my $real_formula = "";
    for(my $i = 0; $i <= $n; $i += 1) {
        $formula = $formula.'\['."l_$i(x) = ";
        $real_formula = $real_formula."$y_values[$i] * ";

        for(my $j = 0; $j <= $n; $j += 1) {
            if ($i != $j) {
                $formula = $formula."{x - x_$j".' \over '."x_$i - x_$j} * ";
            }
        }
        $formula = substr($formula, 0, length($formula) - 2);
        $formula = $formula.' = ';

        for(my $j = 0; $j <= $n; $j += 1) {
            if ($i != $j) {
                my $abs_value = abs($x_values[$j]);
                my $numerator = $x_values[$j] > 0 ? "x - $abs_value" : "x + $abs_value";
                my $denominator = $x_values[$j] > 0 ? "$x_values[$i] - $abs_value" : "$x_values[$i] + $abs_value";
                $formula = $formula."{$numerator".' \over '."$denominator} * ";
                
                my $value = $x_values[$j];
                $numerator = "x - $value";
                $real_formula = $real_formula."($numerator)/($denominator) * "
            }
        }
        $formula = substr($formula, 0, length($formula) - 2);
        $formula = $formula.'\]';

        $real_formula = substr($real_formula, 0, length($real_formula) - 2);
        if ($i + 1 <= $n)
        {
            $real_formula = $real_formula."<br>";
        }
    }

    $formula = $formula.'\['."L(x) = \\sum_{i=0}^{n=$n} (y_i * l_i) = ";
    for(my $i = 0; $i <= $n; $i += 1) {
        if (($i + 1 <= $n) and ($y_values[$i + 1] >= 0))
        {
            $formula = $formula."$y_values[$i] * l_$i(x) + ";
        }
        else
        {
            $formula = $formula."$y_values[$i] * l_$i(x)";
        }
    }
    $formula = $formula.'\]';

    $formula = $formula.'\[L(x) = '.improve_formula($real_formula).'\]';
    $real_formula =~ s/<br>/+/g;
    $real_formula =~ s/x/\$x/g;

    my @calculated_x = ();
    my @calculated_y = ();

    my $x_min = min(@x_values);
    my $x_max = max(@x_values);
    my $h = ($x_max - $x_min) / 10;

    for (my $x = $x_min; $x <= $x_max; $x += $h) {
        my $y = eval($real_formula);

        push @calculated_x, $x;
        push @calculated_y, $y;
    }

    my @data = ([@calculated_x], [@calculated_y]);

    my $graph = new GD::Graph::lines();
    $graph->set(
            title             => "Interpolation",
            x_label           => 'x',
            y_label           => 'y',
            
            x_min_value       => min @x_values,
            x_max_value       => (max @x_values)  + (max @x_values - min @x_values) / 10,
            y_min_value       => min @y_values,
            y_max_value       => (max @y_values)  + (max @y_values - min @y_values) / 10,
        );

    my $path = 'graph.png';
    open (OUT, ">", "public/images/$path") or die "Couldn't open for output: $!";
    binmode(OUT);
    print OUT $graph->plot(\@data)->png();
    close (OUT);

    $graph_path = $path;

    redirect '/';
};

#----------------------------------------------------------------------------------------------------
#input example
#'1 * (x - -2)/(1 + 2) * (x - 2)/(1 - 2) * (x - 4)/(1 - 4)<br>2 * (x - 1)/(-2 - 1) * (x - 2)/(-2 - 2) * (x - 4)/(-2 - 4)'
sub improve_formula {
    my $formula = $_[0];
    my %improved_formula_coeff = ();

    my @terms = split("<br>", $formula);
    for (@terms)
    {
        my $term = $_;
        $term =~ s/^\s+|\s+$//g;
        my %coeff = improve_term($term);

        #summ the coeffs
        for (keys %coeff) {
            my $value = $coeff{$_};
            if (exists $improved_formula_coeff{$_}) {
                $improved_formula_coeff{$_} += $coeff{$_};
            }
            else {
                $improved_formula_coeff{$_} = $coeff{$_};
            }
        }
    }

    #building a formula
    my $improved_formula = "";
    for my $k (reverse 0..scalar(keys %improved_formula_coeff) - 1) {
        my $value = $improved_formula_coeff{$k};
        my $rounded_value = sprintf("%.2g", $value);
    
        if (exists $improved_formula_coeff{$k - 1}) {
            if ($rounded_value != 0) {
                $improved_formula = $improved_formula."$rounded_value*x^{$k}+";
            }
        }
        else {
            if ($k !=0) {
                $improved_formula = $improved_formula."$rounded_value*x^{$k}";
            }
            else {
                $improved_formula = $improved_formula."$rounded_value";
            }
        }
    }
    $improved_formula =~ s/x\^\{1\}/x/g;
    $improved_formula =~ s/\+\-/\-/g;
    return $improved_formula;
}

sub improve_term {
    my $inp = $_[0];
    my @multipliers = split('\*', $inp);
    #calculating k
    my $k = 1;
    my @numerators = ();
    for (my $i = 0; $i < scalar @multipliers; $i++) {
        my $m = $multipliers[$i];
        $m =~ s/^\s+|\s+$//g;

        my @parts = split('/', $m);
        if ($i == 0) {
            $k *= $parts[0];
        }
        else {
            $k /= eval($parts[1]);
            push @numerators, $parts[0];
        }
    }

    #calculating coeffs
    my %coeff = ();
    for (0..scalar @numerators) {
        %coeff = (%coeff, $_, 0);
    }
    $coeff{0} = 1;

    for my $numerator (@numerators) {
        my $a_coeff = 1;
        my $b_coeff = substr($numerator, index($numerator, '-') + 2);
        $b_coeff = substr($b_coeff, 0, length($b_coeff) - 1);
        $b_coeff = -$b_coeff;

        #copying coeffs
        my %old_coeff = ();
        foreach (keys %coeff) {
            my $value = $coeff{$_};
            %old_coeff = (%old_coeff, $_, $value);
        }    

        #updating coeffs
        $coeff{0} = $old_coeff{0} * $b_coeff;
        for (keys %coeff) {
            if ($_ != 0) {
                $coeff{$_} = $old_coeff{$_} * $b_coeff + $old_coeff{$_ - 1} * $a_coeff;
            }
        }
    }

    #multiplying coeffs by k
    for (keys %coeff) {
        my $value = $coeff{$_};
        $coeff{$_} = $value * $k;
    }

    return %coeff;
}
