package GHSWorkspaceCreator;

# ************************************************************
# Description   : A GHS Workspace creator for version 4.x
# Author        : Chad Elliott
# Create Date   : 7/3/2002
# ************************************************************

# ************************************************************
# Pragmas
# ************************************************************

use strict;

use GHSProjectCreator;
use WorkspaceCreator;
use GHSPropertyBase;

use vars qw(@ISA);
@ISA = qw(GHSPropertyBase WorkspaceCreator);

# ************************************************************
# Data Section
# ************************************************************

my %directives = ('I'          => 1,
                  'L'          => 1,
                  'D'          => 1,
                  'l'          => 1,
                  'G'          => 1,
                  'non_shared' => 1,
                  'bsp'        => 1,
                  'os_dir'     => 1,
                 );
my $tgt;
my $integrity  = '[INTEGRITY Application]';
my @integ_bsps;

# ************************************************************
# Subroutine Section
# ************************************************************

sub compare_output {
  #my $self = shift;
  return 1;
}


sub workspace_file_name {
  return $_[0]->get_modified_workspace_name('default', '.gpj');
}

sub is_absolute_path {
  my $path = shift;
  return ($path =~ /^\/.+/ || $path =~ /^[a-zA-Z]:.+/);
}

sub pre_workspace {
  my($self, $fh) = @_;
  my $crlf = $self->crlf();
  my $prjs = $self->get_projects();

  ## Take the primaryTarget from the first project in the list
  if (defined $$prjs[0]) {
    my $fh      = new FileHandle();
    my $outdir  = $self->get_outdir();
    my $fullpath = is_absolute_path($$prjs[0]) ? $$prjs[0] : "$outdir/$$prjs[0]";

    if (open($fh, $fullpath)) {
      while(<$fh>) {
        if (/^#primaryTarget=(.+)$/) {
          $tgt = $1;
          last;
        }
      }
      close($fh);
    }
  }

  ## Try to read the INTEGRITY installation directory and BSP name from environment.
  ## Default values are the installation directory on Windows and the BSP name
  ## for the simulator for PowerPC architecture.
  my $ghs_os_dir = defined $ENV{GHS_OS_DIR} ? $ENV{GHS_OS_DIR} : 'C:\ghs\int1146';
  my $ghs_bsp_name = defined $ENV{GHS_BSP_NAME} ? $ENV{GHS_BSP_NAME} : "sim800";

  ## Print out the preliminary information
  print $fh "#!gbuild$crlf",
            "import ACE_ROOT$crlf",
            "import TAO_ROOT$crlf",
            'defineConfig(Debug dbg "")', $crlf,
            'defineConfig(Release rel "")', $crlf,
            "macro __OS_DIR=$ghs_os_dir$crlf",
            "macro __BSP_NAME=$ghs_bsp_name$crlf",
            "macro __BSP_DIR=\${__OS_DIR}\\\${__BSP_NAME}$crlf",
            "macro __BUILD_DIR=\${ACE_ROOT}\\build$crlf",
            "macro __LIBS_DIR_BASE=\${__OS_DIR}\\libs$crlf",
            "primaryTarget=$tgt$crlf",
            "customization=\${__OS_DIR}\\target\\integrity.bod$crlf",
            "[Project]$crlf",
            "\t-gcc$crlf",
            "\t--c++11$crlf",
            "\t:sourceDir=.$crlf",
            "\t:optionsFile=\${__OS_DIR}\\target\\\${__BSP_NAME}.opt$crlf",
            "\t-I\${ACE_ROOT}$crlf",
            "\t-I\${TAO_ROOT}$crlf",
            "\t-language=cxx$crlf",
            "\t--new_style_casts$crlf",
            "\t-non_shared$crlf",
            "\t{config(dbg)}-G$crlf";
}

# Write a .int file processed by the Integrate tool to create a dynamic download image.
# This file creates a single virtual AddressSpace with specific assumptions such as
# the language being used is C++, the heap size, stack length of the Initial Task.
# Specific application may need to update the generated .int file according to its needs.
# For example, if the application requires working with a file system, use the MULTI IDE
# GUI to add a file system module to the application; this will automatically update the
# .int file. If the application requires more heap memory, manually update the HeapSize
# line to increase the heap size.
sub create_integrity_project {
  my($self, $int_proj, $project, $type, $target) = @_;
  my $outdir   = $self->get_outdir();
  my $crlf     = $self->crlf();
  my $fh       = new FileHandle();
  my $int_file = $int_proj;
  $int_file =~ s/\.gpj$/.int/;
  my $int_file_base = $self->mpc_basename($int_file);
  my $project_base = $self->mpc_basename($project);

  my $int_proj_path = is_absolute_path($int_proj) ? $int_proj : "$outdir/$int_proj";
  if (open($fh, ">$int_proj_path")) {
    ## First print out the project file
    print $fh "#!gbuild$crlf",
              "\t$integrity$crlf",
              "$project_base\t\t$type$crlf",
              "$int_file_base$crlf";
    foreach my $bsp (@integ_bsps) {
      print $fh "$bsp$crlf";
    }
    close($fh);

    ## Next create the integration file
    my $int_path = is_absolute_path($int_file) ? $int_file : "$outdir/$int_file";
    if (open($fh, ">$int_path")) {
      print $fh "Kernel$crlf",
                "\tFilename\t\t\tDynamicDownload$crlf",
                "EndKernel$crlf$crlf",
                "AddressSpace$crlf",
                "\tFilename\t\t\t$target$crlf",
                "\tLanguage\t\t\tC++$crlf",
                # Default heap size is 64kB.
                # Increase to 2MB here to cover more applications.
                "\tHeapSize\t\t\t0x200000$crlf",
                "\tTask Initial$crlf",
                "\t\tStackLength\t\t0xa000$crlf",
                "\tEndTask$crlf",
                "EndAddressSpace$crlf";
      close($fh);
    }
  }
}


sub mix_settings {
  my($self, $project) = @_;
  my $rh     = new FileHandle();
  my $mix    = $project;
  my $outdir = $self->get_outdir();

  # If the project file path is already an absolute path, use it.
  my $fullpath = is_absolute_path($project) ? $project : "$outdir/$project";

  ## Things that seem like they should be set in the project
  ## actually have to be set in the controlling project file.
  if (open($rh, $fullpath)) {
    my $crlf = $self->crlf();
    my $integrity_project = (index($tgt, 'integrity') >= 0);
    my($int_proj, $int_type, $target);

    while(<$rh>) {
      # Don't need to add compiler/linker options to the workspace file.
      # The .gpj file for each individual project should have those already.
      # In the workspace file, only need to list the child projects.
      if (/^\s*(\[(Program|Library|Subproject)\])\s*$/) {
        my $type = $1;
        if ($integrity_project && $type eq '[Program]') {
          $int_proj = $project;             #E.g., tests/MyTest.gpj
          $int_proj =~ s/(\.gpj)$/_int$1/;  #E.g., tests/MyTest_int.gpj
          $int_type = $type;                #E.g., [Program]
          $mix =~ s/(\.gpj)$/_int$1/;       #E.g., tests/MyTest_int.gpj
          $type = $integrity;               # [INTEGRITY Application]
        }
        $mix .= "\t\t$type$crlf";
      }
      elsif (/^\s*(\[Shared Object\])\s*$/) {
        $mix .= "\t\t$1$crlf";
      }
      elsif ($integrity_project && /^(.*\.bsp)\s/) {
        push(@integ_bsps, $1);
      }
      else {
        if (/^\s*\-((\w)\w*)/) {
          ## If this is an integrity project, we need to find out
          ## what the output file will be for the integrate file.
          if (defined $int_proj && /^\s*\-o\s+(.*)\s$/) {
            $target = $1;
          }
        }
      }
    }
    if (defined $int_proj) {
      $self->create_integrity_project($int_proj, $project,
                                      $int_type, $target);
    }
    close($rh);
  }

  return $mix;
}


sub write_comps {
  my($self, $fh) = @_;

  ## Print out each project
  foreach my $project ($self->sort_dependencies($self->get_projects(), 0)) {
    print $fh $self->mix_settings($project);
  }
}

1;
