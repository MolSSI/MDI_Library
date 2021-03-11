MODULE MDI_IMPLEMENTATION

  USE mpi
  USE ISO_C_binding
  USE mdi,              ONLY : MDI_Init, MDI_Send, MDI_INT, MDI_CHAR, MDI_NAME_LENGTH, &
       MDI_Accept_Communicator, MDI_Recv_Command, MDI_Recv, MDI_Conversion_Factor, &
       MDI_Set_Execute_Command_Func, MDI_MPI_get_world_comm, MDI_DOUBLE, MDI_BYTE, &
       MDI_ENGINE, MDI_Get_Role, MDI_Register_Command, MDI_Register_Node, &
       MDI_Register_Callback, MDI_COMMAND_LENGTH, MDI_MPI_get_world_comm

  IMPLICIT NONE

  INTEGER, PARAMETER :: dp = selected_real_kind(15, 307)

  INTEGER :: comm
  LOGICAL :: terminate_flag = .false.

CONTAINS

  SUBROUTINE MDI_Plugin_init() bind ( C, name="MDI_Plugin_init" )
    INTEGER :: ierr, world_comm

    ! Call MDI_Init
    world_comm = MPI_COMM_WORLD
    CALL MDI_Init("-role ENGINE -method LINK -name MM -driver_name driver", world_comm, ierr)

    ! Get the MPI intra-communicator over which this plugin will run
    CALL MDI_MPI_get_world_comm(world_comm, ierr);

    ! Perform one-time operations required to establish a connection with the driver
    CALL initialize_mdi()

    ! Respond to commands from the driver
    CALL respond_to_commands()

  END SUBROUTINE MDI_Plugin_init


  SUBROUTINE initialize_mdi()
    INTEGER :: ierr, role

    PROCEDURE(execute_command), POINTER :: generic_command => null()
    TYPE(C_PTR)                         :: class_obj
    generic_command => execute_command

    ! Confirm that the code is being run as an ENGINE
    call MDI_Get_Role(role, ierr)
    IF ( role .ne. MDI_ENGINE ) THEN
       WRITE(6,*)'ERROR: Must run engine_f90 as an ENGINE'
    END IF

    ! Register the commands
    CALL MDI_Register_Node("@DEFAULT", ierr)
    CALL MDI_Register_Command("@DEFAULT", "EXIT", ierr)
    CALL MDI_Register_Command("@DEFAULT", "<NATOMS", ierr)
    CALL MDI_Register_Command("@DEFAULT", "<COORDS", ierr)
    CALL MDI_Register_Command("@DEFAULT", "<FORCES", ierr)
    CALL MDI_Register_Command("@DEFAULT", "<FORCES_B", ierr)
    CALL MDI_Register_Node("@FORCES", ierr)
    CALL MDI_Register_Command("@FORCES", "EXIT", ierr)
    CALL MDI_Register_Command("@FORCES", "<FORCES", ierr)
    CALL MDI_Register_Command("@FORCES", ">FORCES", ierr)
    CALL MDI_Register_Callback("@FORCES", ">FORCES", ierr)

    ! Connct to the driver
    CALL MDI_Accept_Communicator(comm, ierr)

    ! Set the generic execute_command function
    CALL MDI_Set_Execute_Command_Func(generic_command, class_obj, ierr)

  END SUBROUTINE initialize_mdi


  SUBROUTINE respond_to_commands()
    CHARACTER(len=:), ALLOCATABLE :: command
    INTEGER :: ierr

    ALLOCATE( character(MDI_COMMAND_LENGTH) :: command )

    ! Respond to the driver's commands
    response_loop: DO

       CALL MDI_Recv_Command(command, comm, ierr)

       CALL execute_command(command, comm, ierr)

       IF ( terminate_flag ) EXIT

    END DO response_loop

    DEALLOCATE( command )

  END SUBROUTINE respond_to_commands


  SUBROUTINE execute_command(command, comm, ierr)
    IMPLICIT NONE

    CHARACTER(LEN=*), INTENT(IN)  :: command
    INTEGER, INTENT(IN)           :: comm
    INTEGER, INTENT(OUT)          :: ierr

    INTEGER                       :: icoord
    INTEGER                       :: natoms, count
    DOUBLE PRECISION, ALLOCATABLE :: coords(:), forces(:)

    ! set dummy molecular properties
    natoms = 10
    ALLOCATE( coords( 3 * natoms ) )
    DO icoord = 1, 3 * natoms
       coords(icoord) = 0.1_dp * ( icoord - 1 )
    END DO
    ALLOCATE( forces( 3 * natoms ) )
    DO icoord = 1, 3 * natoms
       forces(icoord) = 0.01_dp * ( icoord - 1 )
    END DO
 
    SELECT CASE( TRIM(command) )
    CASE( "EXIT" )
       terminate_flag = .true.
    CASE( "<NATOMS" )
       CALL MDI_Send(natoms, 1, MDI_INT, comm, ierr)
    CASE( "<COORDS" )
       CALL MDI_Send(coords, 3 * natoms, MDI_DOUBLE, comm, ierr)
    CASE( "<FORCES" )
       CALL MDI_Send(forces, 3 * natoms, MDI_DOUBLE, comm, ierr)
    CASE( "<FORCES_B" )
       count = 3 * natoms * sizeof(1.d0)
       CALL MDI_Send(forces, count, MDI_BYTE, comm, ierr)
    CASE DEFAULT
       WRITE(6,*)'Error: command not recognized'
    END SELECT

    DEALLOCATE( coords, forces )

    ierr = 0
  END SUBROUTINE execute_command

END MODULE MDI_IMPLEMENTATION