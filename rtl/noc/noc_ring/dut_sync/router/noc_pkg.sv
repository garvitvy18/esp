// This package defines constants, data types and functions for the Ring NoC

package noc;

    //
    // Configuration parameters
    //

    // Coordinates
    parameter int unsigned xMax = 8;
    parameter int unsigned yMax = 8;

    // Message Type
    parameter int unsigned messageTypeWidth = 5;
	
    //
    //Ring Size Parameter
    parameter int unsigned kRingSize = 4;

    //
    // Direction constants, types and functions
    //

    // Router ports enable (for ring topology, East, West, and Local ports enabled)
    parameter bit [2:0] AllPorts = 3'b111;  // Enable East, West, and Local
    parameter bit [2:0] TopLeftRouterPorts = 3'b110;  // Enable East and Local
    parameter bit [2:0] TopRightRouterPorts = 3'b101; // Enable West and Local
    parameter bit [2:0] BottomLeftRouterPorts = 3'b110; // Enable East and Local
    parameter bit [2:0] BottomRightRouterPorts = 3'b101; // Enable West and Local

    typedef enum logic [2:0] {
        kLocalPort = 3'd2,   // Local (for local communication)
        kEastPort  = 3'd1,  // Clockwise (East)
        kWestPort  = 3'd0  // Counter-clockwise (West)
    } noc_port_t;

    // One-hot encoding of the ports for routing
    typedef struct packed {
        logic go_local;
        logic go_east;
        logic go_west;
    } direction_t;

    // Function to return one-hot encoding for a given port
    function automatic direction_t get_onehot_port(input noc_port_t port);
        get_onehot_port.go_west  = (port == kWestPort);
	get_onehot_port.go_east  = (port == kEastPort);
	get_onehot_port.go_local = (port == kLocalPort);
    endfunction

    // Function to convert direction_t to noc_port_t
    function automatic noc_port_t get_direction(input direction_t direction);
        if (direction.go_east) return kEastPort;
        else if (direction.go_west) return kWestPort;
        else if (direction.go_local) return kLocalPort;
        else return kEastPort;  // Default to East if nothing matches
    endfunction

    // Convert integer to corresponding noc_port_t
    function automatic noc_port_t int2noc_port(input int i);
        case (i)
            0: return kWestPort;
            1: return kEastPort;
            2: return kLocalPort;
            default: return kEastPort;
        endcase
    endfunction

    // Parameters for East, West, and Local ports
    parameter direction_t goEast  = get_onehot_port(kEastPort);
    parameter direction_t goWest  = get_onehot_port(kWestPort);
    parameter direction_t goLocal = get_onehot_port(kLocalPort);

    //
    // Coordinates types
    //
    parameter int unsigned xWidth = $clog2(xMax);
    parameter int unsigned yWidth = $clog2(yMax);

    typedef struct packed {
//        logic [yWidth-1:0] y;
        logic [xWidth-1:0] x;
    } xy_t;

    //
    // Flow control types
    //
    typedef enum logic {
        kFlowControlAckNack = 1'b0,
        kFlowControlCreditBased = 1'b1
    } noc_flow_control_t;

    //
    // Packet info encoding
    //
    typedef logic [messageTypeWidth-1:0] message_t;

    typedef struct packed {
        logic head;
        logic tail;
    } preamble_t;

endpackage

