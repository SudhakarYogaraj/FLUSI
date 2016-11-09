subroutine convert_to_wing_system(help)
  use mpi
  use vars
  use p3dfft_wrapper
  use solid_model
  use insect_module
  use slicing
  use ghosts
  use interpolation
  use penalization ! mask array etc

  implicit none
  logical, intent(in) :: help

  real(kind=pr)          :: t1,t2
  real(kind=pr)          :: time
  integer                :: ix,iy,iz
  character (len=strlen) :: infile
  ! arrays needed for interpolation
  real(kind=pr),dimension(:,:,:),allocatable :: u_org,u_interp
  ! this is the insect we're using (object oriented)
  type(diptera) :: Insect
  ! this is the solid model beams:
  type(solid), dimension(1:nBeams) :: beams
  real(kind=pr) :: x_wing(1:3),x_glob(1:3),M_wing_r(1:3,1:3),M_wing_l(1:3,1:3),M_body(1:3,1:3)
  real(kind=pr) :: u1,u2

  ! Set method information in vars module.
  method="fsi" ! We are doing fluid-structure interactions
  nf=1    ! We are evolving one field (that means 1 integrating factor)
  nd=3*nf ! The one field has three components.
  neq=nd  ! number of equations, can be higher than 3 if using passive scalar
  nrw=1   ! number of real valued work arrays
  ncw=1   ! number of complex values work arrays (decide that later)
  nrhs=2  ! number of right-hand side registers

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --convert-to-wing-system PARAMS.ini input_0000.h5 output_0000.h5"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! Convert a file to the (left) wings coordinate system"
    write(*,*) "! We read a field from file, which we assume to be a scalar field (or vector component)"
    write(*,*) "! given as q(x,y,z) where x,y,z are understood in the global coordinate system"
    write(*,*) "! "
    write(*,*) "! We now want q(xw,yw,zw) in the wing coordinate system. The output field has the same"
    write(*,*) "! spacing dx,dx,dz as the input field, and the coordinates are "
    write(*,*) "! -xl/2 <= xw <= xl/2"
    write(*,*) "! -yl/2 <= yw <= yl/2"
    write(*,*) "! -zl/2 <= zw <= zl/2"
    write(*,*) "! "
    write(*,*) "! For each of these points in the wing system, we compute the corresponding global coordinate"
    write(*,*) "! and interpolate the input field at this point. Note we require the PARAMS file to know what"
    write(*,*) "! motion protocoll to use for wings AND body (this is why we cannot use this with free_flight)"
    write(*,*) "! The time is read from the input file."
    write(*,*) "! "
    write(*,*) "! Note the wing span axis is y, while the chord ix x. z is wing normal."
    write(*,*) "! "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: no (since interpolation is tedious on MPI distributed data)"
    return
  endif

  if (mpisize/=1) then
    write(*,*) "./flusi -p --convert-to-wing-system IS A SERIAL ROUTINE; USE 1CPU ONLY"
    ! call abort(40004)
  endif
  !-----------------------------------------------------------------------------
  ! Read input parameters
  !-----------------------------------------------------------------------------
  allocate(lin(nf)) ! Set up the linear term
  if (root) write(*,'(A)') '*** info: Reading input data...'
  ! get filename of PARAMS file from command line
  call get_command_argument(3,infile)
  ! read all parameters from that file
  call get_params(infile,Insect,.true.)

  !-----------------------------------------------------------------------------
  ! ghost points. we need that for interpolation
  !-----------------------------------------------------------------------------
  ng=1 ! one ghost point
  if (root) write(*,'("Set up ng=",i1," ghost points")') ng

  ! initialize code and domain decomposition, but do not use FFTs
  call decomposition_initialize()
  ! Setup communicators used for ghost point update
  call setup_cart_groups

  !-----------------------------------------------------------------------------
  ! Allocate memory:
  !-----------------------------------------------------------------------------
  allocate( u_org(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)) )
  ! interpolated field has ghost nodes
  allocate( u_interp(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3)) )

  if (iMask/="Insect") then
    call abort(7774,"transforming to wing system makes no sense if not applied to an insect")
  endif

  if (Insect%BodyMotion=="free_flight") then
    ! we currently require a prescribed body to perform the transformation: in the
    ! free flight case, we would have to get the position/orientation for example
    ! from the kinematics.t log-file.
    call abort(44432,"this module currently will not run with free flight, as body position is unkown")
  endif

  !*****************************************************************************
  ! main (active) part of this postprocessing tool
  !*****************************************************************************
  ! read in the input file to be transformed
  call get_command_argument(4,infile)
  call read_single_file ( infile, u_org )
  call fetch_attributes(infile,nx,ny,nz,xl,yl,zl,time,nu)
  ! synchronize ghosts
  u_interp(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)) = u_org
  call synchronize_ghosts( u_interp )

  !-----------------------------------------------------------------------------
  ! fetch current motion state of the insect
  !-----------------------------------------------------------------------------
  call BodyMotion (time, Insect)
  call FlappingMotion_right (time, Insect)
  call FlappingMotion_left (time, Insect)
  call StrokePlane (time, Insect)
  call body_rotation_matrix( Insect, M_body )
  call wing_right_rotation_matrix( Insect, M_wing_r )
  call wing_left_rotation_matrix( Insect, M_wing_l )


  do iz = 0,nz-1!ra(3), rb(3)
    do iy = 0,ny-1!ra(2), rb(2)
      do ix = 0,nx-1!ra(1), rb(1)
        ! define the position in the wing coordinate system (we seek for u in this
        ! coordinate system, so our output matrix is to be understood in this)
        x_wing = (/ dble(ix)*dx, dble(iy)*dy, dble(iz)*dz /) - (/xl,yl,zl/)/2.d0

        x_glob = Insect%xc_body_g+ matmul(transpose(M_body), (matmul(transpose(M_wing_l),x_wing)+Insect%x_pivot_l) )

        call trilinear_interp_ghosts(x_glob,u_interp,u1)!u_org(ix,iy,iz))
        u2 = mpimax(u1)
        if ( on_proc( (/ix,iy,iz/)  ) ) then
          u_org(ix,iy,iz) = u2
        endif


      enddo
    enddo
  enddo

  where (u_org < -9.0d10)
    u_org = 0.d0
  end where

  call get_command_argument(5,infile)
  if (root) write(*,*) "ouput will be written to "//infile
  call save_field_hdf5(time, infile, u_org)

  !-----------------------------------------------------------------------------
  ! Deallocate memory
  !-----------------------------------------------------------------------------
  deallocate(u_org,u_interp)
  ! Clean insect (the globally stored arrays for Fourier coeffs etc..)
  call insect_clean(Insect)
end subroutine convert_to_wing_system
