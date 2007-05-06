package Module::Packaged::Report;
use strict;
use warnings;

use Module::Packaged;
use Module::Packaged::Generate;
use HTML::Template;
use File::Spec;
use File::Path   qw(mkpath);
use Parse::CPAN::Packages;
use App::Cache;

use Data::Dumper qw(Dumper);

our $VERSION = '0.03';

my @distributions = (
    {
        title   => 'Debian',
        name    => 'debian',
        source  => 'debian_unstable',
        real    => 'Debian Unstable',
    },
    {
        title   => '',
        name    => 'debian',
        source  => 'debian_stable',
        real    => 'Debian Stable',
    },
    {
        title   => '',
        name    => 'debian',
        source  => 'debian_testing',
        real    => 'Debian Testing',
    },
    {
        title   => '',
        name    => 'ubuntu',
        source  => 'ubuntu_gutsy',
        real    => 'Ubuntu Gutsy Gibbon 7.10',
    },
    {
        title   => 'Ubuntu',
        name    => 'ubuntu',
        source  => 'ubuntu_feisty',
        real    => 'Ubuntu Feisty Fawn 7.04',
    },
    {
        title   => '',
        name    => 'ubuntu',
        source  => 'ubuntu_edgy',
        real    => 'Ubuntu Edgy Eft 6.10',
    },
    {
        title   => '',
        name    => 'ubuntu',
        source  => 'ubuntu_dapper',
        real    => 'Ubuntu Dapper Drake 6.06',
    },
    {
        title   => '',
        name    => 'ubuntu',
        source  => 'ubuntu_breezy',
        real    => 'Ubuntu Breezy Badger 5.10',
    },
    {
        title   => '',
        name    => 'ubuntu',
        source  => 'ubuntu_hoary',
        real    => 'Ubuntu Hoary Hedgehog 5.04',
    },
    {
        title   => '',
        name    => 'ubuntu',
        source  => 'ubuntu_warty',
        real    => 'Ubuntu Warty Warthog 4.10',
    },
    {
        title   => 'Fedora',
        name    => 'fedora',
        source  => 'fedora',
        real    => 'Fedora FC2',
    },
    {
        title   => 'FreeBSD',
        name    => 'freebsd',
        source  => 'freebsd',
        real    => 'FreeBSD',
    },
    {
        title   => 'Mandriva',
        name    => 'mandriva',
        source  => 'mandriva',
        real    => 'Mandriva',
    },
    {
        title  => 'OpenBSD',
        name   => 'openbsd',
        source => 'openbsd',
        real   => 'OpenBSD',
    },
    {
        title  => 'Suse',
        name   => 'suse',
        source => 'suse',
        real   => 'Suse',
    },
    {
        title  => 'Gentoo',
        name   => 'gentoo',
        source => 'gentoo',
        real   => 'Gentoo',
    },
    {
        title  => 'ActivePerl 8xx Windows',
        name   => 'activeperl_8xx_windows',
        source => 'activeperl_8xx_windows',
        real   => 'ActivePerl 8xx Windows',
    },
    {
        title  => '',
        name   => 'activeperl_8xx_solaris',
        source => 'activeperl_8xx_solaris',
        real   => 'ActivePerl 8xx Solaris',
    },
    {
        title  => '',
        name   => 'activeperl_8xx_linux',
        source => 'activeperl_8xx_linux',
        real   => 'ActivePerl 8xx Linux',
    },
    {
        title  => '',
        name   => 'activeperl_8xx_hp-ux',
        source => 'activeperl_8xx_hp-ux',
        real   => 'ActivePerl 8xx HP-UX',
    },
    {
        title  => '',
        name   => 'activeperl_8xx_darwin',
        source => 'activeperl_8xx_darwin',
        real   => 'ActivePerl 8xx Darwin',
    },
);

my @letters = ('A'..'Z');


sub new {
    my ($class, %opts) = @_;
    usage() if $opts{help};
    usage() if not ($opts{test} xor $opts{real});

    my $self = bless {}, $class;
    $self->{opts} = \%opts;
    #$self->{p} = Module::Packaged->new();
    $self->{_timestamp} = time;

    my $cache = App::Cache->new({ ttl => 60 * 60 * 24 *7  });
    my $data = $cache->get_url('http://www.cpan.org/modules/02packages.details.txt.gz');
    $self->{pcp} = Parse::CPAN::Packages->new($data);
    $self->{count} = {};

    return $self;
}

sub collect_data {
    my ($self) = @_;
    $self->{p} = Module::Packaged::Generate->new;
    $self->{p}->fetch_all;
}


sub _timestamp {
    my ($self) = @_;
    return scalar localtime $self->{_timestamp};
}

sub _list_packages {
    my ($self) = @_;
    if ($self->{opts}{test}) {
        return qw(AcePerl Acme-Buffy CGI DBD-Pg DBI Spreadsheet-ParseExcel);
    } else {
        return sort keys %{ $self->{p}{data} };
    }
}

sub generate_html_report {
    my ($self) = @_;

    my $dir = $self->_dir;
    mkpath (File::Spec->catfile($dir, 'letters'));
    mkpath (File::Spec->catfile($dir, 'distros'));
    mkpath (File::Spec->catfile($dir, 'authors'));

    $self->_save_style;

    $self->_process_data;

    foreach my $letter (@letters) {
        $self->_generate_report_for_letter($letter);
    }

    $self->_generate_per_distribution_reports;
    $self->_generate_per_author_report;
    $self->_generate_main_index;
}

sub _generate_main_index {
    my ($self) = @_;
    my @letters_hashes = map {{letter => $_}} @letters;
    my @distros;
    foreach my $d (@distributions) {
        push @distros, {
            title => $d->{real},
            name  => $d->{source},
            count => $self->{count}{ $d->{source} },
        };
    }

    $self->create_file(
            template => $self->_index_tmpl(),
            filename => File::Spec->catfile($self->_dir, "index.html"),
            params => {
                letters => \@letters_hashes,
                footer  => $self->_footer(),
                cpan    => $self->{count}{cpan},
                distros => \@distros,
            },
    );
}

sub _generate_per_distribution_reports {
    my ($self) = @_;
    foreach my $distro (keys %{ $self->{distros} }) {
        #print "$distro\n";
        my $name = $distro eq 'mandrake' ? 'mandriva' : $distro;

        $self->create_file(
            template => $self->_modules_in_distro_report_tmpl,
            filename => File::Spec->catfile($self->_dir, 'distros', "$name.html"),
            params => {
                distro  => ucfirst($name),
                modules => $self->{distros}{$distro},
            },
        );
    }
}

sub _generate_per_author_report {
    my ($self) = @_;

    foreach my $cpanid (keys %{ $self->{authors} }) {
        my @modules;
        foreach my $module (@{ $self->{authors}{$cpanid}}) {
            my @dists;
            foreach my $d (@distributions) {
                push @dists, {version => $module->{ $d->{source} } || ''}
            }
            push @modules, {
                    name => $module->{name},
                    cpan => $module->{cpan},
                    distros => \@dists,
                };
        }

        $self->create_file(
            template => $self->_per_author_report_tmpl,
            filename => File::Spec->catfile($self->_dir, 'authors', "$cpanid.html"),
            params => {
                modules      => \@modules,
                footer       => $self->_footer(),
                cpanid       => $cpanid,
            },
        );
    }
    my @cpanids = map {{cpanid => $_}} sort keys %{ $self->{authors} };
    $self->create_file(
        template => $self->_authors_index_tmpl(),
        filename => File::Spec->catfile($self->_dir, 'authors', "index.html"),
        params => {
            ids      => \@cpanids,
            footer   => $self->_footer(),
        },
    );
}

sub _process_data {
    my ($self) = @_;

    foreach my $dash_name ($self->_list_packages) {
        my $dists = $self->{p}->check($dash_name);
        my $name = $dash_name;
        $name =~ s/-/::/g;

        $self->{count}{cpan}++;
        next if 1 >= keys %$dists; # skip modules that are only on CPAN

        # collect data for list of modules in a single distro
        foreach my $distro (keys %$dists) {
            next if $distro eq 'cpan';
            $self->{count}{$distro}++;
            push @{ $self->{distros}{$distro} }, {
                name    => $name,
                version => $dists->{$distro},
                cpan    => $dists->{cpan},
            };
        }

        # collect data for modules by each author
        my $m = $self->{pcp}->package($name);
        $dists->{name} = $name;
        if ($m) {
            my $d = $m->distribution;
            push @{ $self->{authors}{uc $d->cpanid} }, $dists;
        } else {
            #warn "No package for '$name'\n";
        }
    }
}


sub _generate_report_for_letter {
    my ($self, $letter) = @_;

    my @module_names = grep {/^$letter/i} $self->_list_packages;
    my @modules;
    foreach my $dash_name (@module_names) {
        my @dists;
        my $dists = $self->{p}->check($dash_name);
        my $name = $dash_name;
        $name =~ s/-/::/g;
        foreach my $d (@distributions) {
            next if not $d->{title};
            push @dists, {version => $dists->{ $d->{source} } || ''};
        }

        push @modules, {
                    cpan    => $dists->{cpan},
                    name    => $name,
                    distros => \@dists,
                    };
    }

    my @distribution_titles = map { {title => $_->{title} } }
                                grep { $_->{title} } @distributions;

    $self->create_file(
            template => $self->_report_tmpl(),
            filename => File::Spec->catfile($self->_dir, 'letters', "$letter.html"),
            params => {
                distributions => \@distribution_titles,
                modules       => \@modules,
                footer        => $self->_footer(),
            },
    );
}

sub create_file {
    my ($self, %args) = @_;

    my $t = HTML::Template->new_scalar_ref(\$args{template}, die_on_bad_params => 1);
    $t->param(%{ $args{params} });
    open my $fh, '>', $args{filename}  or die "Could not open '$args{filename}' $!";
    print {$fh} $t->output;
}

sub _footer {
    my ($self) = @_;
    
    my $template = $self->_footer_tmpl();
    my $t = HTML::Template->new_scalar_ref(\$template, die_on_bad_params => 1);
    $t->param(timestamp    => $self->_timestamp);
    $t->param(mp_version   => $Module::Packaged::VERSION);
    $t->param(mpr_version  => $VERSION);
    return $t->output;
}

 
sub _dir {
    my ($self) = @_;
    return $self->{opts}{dir} || './report';
}


sub usage {
    print <<"USAGE";
Usage: $0
            --test            test run using small number of modules  
            --real            real run
                              You have to provide either test or real

            --dir DIR         name of the directory where the reports are generated (defaults to ./report)

            --help            this help
USAGE

    exit;
}



############################### Templates ########################
# for the time we might generate the column titles
#<tr>
#  <td></td>
#  <TMPL_LOOP packagers>
#  <td><TMPL_VAR name></td>
#  </TMPL_LOOP>
#</tr>

sub _save_style {
    my ($self) = @_;

    my $filename = File::Spec->catfile($self->_dir, "style.css");
    open my $fh, '>', $filename or die $!;
    print {$fh} <<'END_CSS';
<style type="text/css"> 
 
first_one_is_not_seen_by_firefox { 
} 
 
h1 { 
    color: #000000; 
    text-align: center; 
} 
 
body { 
    background-color: #FFFFFF; 
    font-size: 12px;
} 
table {
    border-width: 1px;
    border-style: solid;
}
td {
    border-width: 1px;
    border-style: solid;
    text-align: center;
    font-size: 12px;
}

.internal {
    border-style: none;
}

.name {
    text-align: left;
}
</style>

END_CSS

}

sub _authors_index_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in Distributions per author</title>
  <link rel="stylesheet" type="text/css" href="../style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<center><h1>CPAN Modules in Distributions per author</h1></center>
<p>
<a href="../index.html">index</a>
<p>
<TMPL_LOOP ids>
  <a href="<TMPL_VAR cpanid>.html"><TMPL_VAR cpanid></a><br />
</TMPL_LOOP>
<TMPL_VAR footer>
</body>
</html>
END_TMPL

}
sub _index_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in Distributions</title>
  <link rel="stylesheet" type="text/css" href="style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<center><h1>CPAN Modules in Distributions</h1></center>
Modules starting with letter
<TMPL_LOOP letters>
  <a href="letters/<TMPL_VAR letter>.html"><TMPL_VAR letter></a>&nbsp;
</TMPL_LOOP>
<p>
<a href="authors/">Authors</a>
<p>
Total number of modules in each distribution:
<table>
<tr><td class="name">CPAN</td><td><TMPL_VAR cpan></td></tr>
<TMPL_LOOP distros>
<tr><td class="name"><TMPL_VAR title></td><td><a href="distros/<TMPL_VAR name>.html"><TMPL_VAR count></a></td></tr>
</TMPL_LOOP>
</table>

<p>
Wishes: 
<ul>
 <li>Include <strike>Ubuntu</strike>, RedHat, <strike>Gentoo</strike>, Sun Solaris, AIX, HP-UNIX etc</li>
 <li><strike>Separate Debian stable and testing</strike></li>
 <li>At least in Ubuntu separate the report for standard, universe and backport repositories</li>
 <li><strike>Include ActiveState distributions</strike></li>
 <li>Include ActiveState distributions for older Perl versions</li>
</ul>
</p>

<TMPL_VAR footer>
</body>
</html>
END_TMPL

}

sub _modules_in_distro_report_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in <TMPL_VAR distro></title>
  <link rel="stylesheet" type="text/css" href="../style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<h1>CPAN Modules in <TMPL_VAR distro></h1>
<a href="../index.html">index</a>
<table>
<tr><td>Name</td>
    <td>Version</td>
    <td>Latest on CPAN</td>
<TMPL_LOOP modules><tr><td class="name"><TMPL_VAR name></td><td><TMPL_VAR version></td><td><TMPL_VAR cpan></td></tr>
</TMPL_LOOP>
</table>

<TMPL_VAR footer>

</body>
</html>
END_TMPL

}


sub _per_author_report_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules of <TMPL_VAR cpanid> in Distributions</title>
  <link rel="stylesheet" type="text/css" href="../style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<h1>CPAN Modules  of <TMPL_VAR cpanid> in Distributions</h1>
<a href="../index.html">index</a>
<table>
<tr><td rowspan="2"></td>
    <td rowspan="2">CPAN</td>

    <td colspan="3">Debian</td>
    <td colspan="7">Ubuntu</td>

    <td rowspan="2">Fedora</td>
    <td rowspan="2">FreeBSD</td>
    <td rowspan="2">Mandriva</td>
    <td rowspan="2">OpenBSD</td>
    <td rowspan="2">Suse</td>
    <td rowspan="2">Gentoo</td>

    <td colspan="5">ActivePerl 8xx</td>
</tr>

<tr>
    <td class="internal">Testing</td>
    <td class="internal">Unstable</td>
    <td class="internal">Stable</td>

    <td class="internal">Gutsy Gibbon 7.10</td>
    <td class="internal">Feisty Fawn 7.04</td>
    <td class="internal">Edgy Eft 6.10</td>
    <td class="internal">Dapper Drake 6.06</td>
    <td class="internal">Breezy Badger 5.10</td>
    <td class="internal">Hoary Hedgehog 5.04</td>
    <td class="internal">Warty Warthog 4.10</td>

    <td class="internal">Windows</td>
    <td class="internal">Solaris</td>
    <td class="internal">Linux</td>
    <td class="internal">HP-UX</td>
    <td class="internal">Darwin</td>
</tr>
<TMPL_LOOP modules>
<tr>
<td class="name"><TMPL_VAR name></td>
<td><TMPL_VAR cpan></td>
<TMPL_LOOP distros>
<td><TMPL_VAR version></td>
</TMPL_LOOP>
</tr>
</TMPL_LOOP>
</table>

<TMPL_VAR footer>

</body>
</html>
END_TMPL

}


sub _report_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in Distributions</title>
  <link rel="stylesheet" type="text/css" href="../style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<h1>CPAN Modules in Distributions</h1>
<a href="../index.html">index</a>
<table>
<tr><td></td>
    <td>CPAN</td>
<TMPL_LOOP distributions>
  <td><TMPL_VAR title></td>
</TMPL_LOOP>
<TMPL_LOOP modules>

<tr>
<td class="name"><TMPL_VAR name></td>
<td><TMPL_VAR cpan></td>
<TMPL_LOOP distros>
<td><TMPL_VAR version></td>
</TMPL_LOOP>
</tr>

</TMPL_LOOP>
</table>

<TMPL_VAR footer>

</body>
</html>
END_TMPL

}

sub _footer_tmpl {
    return <<'END_TMPL';
<p>
Report generated on <TMPL_VAR timestamp> 
using <a href="http://search.cpan.org/dist/Module-Packaged-Report">Module::Packaged::Report</a> 
version <TMPL_VAR mpr_version>
and <a href="http://search.cpan.org/dist/Module-Packaged">Module::Packaged</a> version <TMPL_VAR mp_version>. 
Patches to both modules are welcome by the respective authors. Subversion repository of 
<a href="http://svn1.hostlocal.com/szabgab/trunk/Module-Packaged-Report/">Module-Packaged-Report</a>
and the Subversion repository of the patched version of 
<a href="http://svn1.hostlocal.com/szabgab/trunk/Module-Packaged-0.86/">Module-Packaged</a> where you
can see how the data is being collected.
</p>
END_TMPL

}

=head1 NAME

Module::Packaged::Report - Generate report upon packages of CPAN distributions

=head1 SYNOPSIS

Run the create_package_report.pl script that comes with the module.

=head1 DESCRIPTION

Using L<Module::Packaged> to fetch the collected data.

Create table of CPAN modules vs. Distributions (e.g. Linux distributions, Solaris compiled packages etc)
that will show for each module and distro which version (if any) of the CPAN module is available 
for that distro in it standard packaging system.

=head1 METHODS

=head2 new

 my $mpr = Module::Packaged::Report->new(%OPTIONS);

 %OPTIONS can be 

 test => 1   or  real => 1

 help => 1 to get help

 dir => /path/to/dir

  
=head2 generate_html_report;

 $mpr->generate_html_report;


=head1 TODO

Add more distributions.

Coloring, so it will be obvious which distribution carries the latest version and 
which one has a huge? gap.

Explain this!
Total number of modules on cpan is reported as 14329 while www.cpan.org reports 11563.

=head1 See also

L<Parse::Debian::Packages> L<Debian::Package::HTML>

=head1 COPYRIGHT

Copyright (c) 2007 Gabor Szabo. All rights reserved. This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

Gabor Szabo <gabor@pti.co.il>

=cut

1;

