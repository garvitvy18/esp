// Compute next YX positional routing for a 2D mesh NoC
//
// This module determines the next routing direction (lookahead) for the current flit.
// First the coordinates of the next hop are determined based on the routing direction
// encoded in the header flit. Next, the routing direction is updated based on the
// coordinates of the destination router.
// Packets are routed first west or east (X axis), then north or south (Y axis).
// The YX positional routing is proven to be deadlock free.
//
// There is no delay from inputs destination and current_routing to output next_routing.
// Conversely, to improve timing, the local position input is sampled, thus there is a one-cycle
// delay from input position to output next_routing. Note, however, that position is supposed to be
// a static input after initialization, because it encodes the position of the router on the mesh.
//
// Interface
//
// * Inputs
// - clk: clock.
// - position: static input that encodes the x,y coordinates of the router on the mesh.
// - destination: x,y coordinates of the destination router.
// - current_routing: one-hot encoded routing direction for the current hop.
//
// * Outputs
// - next_routing: one-hot encoded routing direction for the next hop.
//

module lookahead_routing (
    input logic clk,
    input noc::xy_t position,        // static input for current router's position (tile)
    input noc::xy_t destination,     // destination coordinates
    input noc::direction_t current_routing, // current routing direction
    output noc::direction_t next_routing  // next hop direction
);

    // Function to compute next routing direction based on ring topology
    function automatic noc::direction_t routing(input noc::xy_t next_position,
                                                input noc::xy_t destination,
						input noc::direction_t current_routing);
	noc::direction_t west,east;
//	west = next_position.x>destination.x?noc::goWest:~noc::goWest;
//	east = next_position.x<destination.x?noc::goEast:~noc::goEast;
  /*      int dist_cw  = (destination.x - next_position.x + noc::kRingSize) % noc::kRingSize;
        int dist_ccw = (next_position.x - destination.x + noc::kRingSize) % noc::kRingSize;
        if (dist_cw == 0 && dist_ccw == 0)
            routing = noc::goLocal; // Already at destination
        else if (dist_cw <= dist_ccw) begin
            east = noc::goEast; // 3'b010
	    west = ~noc::goWest;
	    routing=west&east;
        end else begin
            west = noc::goWest; // 3'b001
	    east = ~noc::goEast;
	    routing=west&east;
        end
*/
	if(next_position.x == destination.x) begin
		routing = noc::goLocal;
	end
	else
		routing = current_routing;
	
//	else if (current_routing.go_west)
//		routing = noc::goWest;
        //routing=west&east;
        // Determine clockwise (East) or counter-clockwise (West) based on destination
       // if (position.x < destination.x) begin
            // If destination is ahead in the ring, route clockwise (East)
          //  routing = noc::goEast;  // Clockwise direction
       // end else if (position.x > destination.x) begin
            // If destination is behind in the ring, route counter-clockwise (West)
           // routing = noc::goWest;  // Counter-clockwise direction
            // If already at destination (same position), route locally
          //  routing = noc::goLocal; // Stay at local port (no movement)
       // end
    endfunction

    // Compute next position for each port (East, West, and Local directions)
    noc::xy_t [1:0] next_position_d, next_position_q;
    
    // East (Clockwise) movement
//    assign next_position_d[noc::kEastPort].x = position.x + 1'b1;  // Move to the next tile (East in the ring)
    //assign next_position_d[noc::kEastPort].y = position.y;         // y-coordinate remains the same

    // West (Counter-clockwise) movement
//    assign next_position_d[noc::kWestPort].x = position.x - 1'b1;  // Move to the previous tile (West in the ring)
    //assign next_position_d[noc::kWestPort].y = position.y;         // y-coordinate remains the same

    // Local movement (when already at the destination)
    //assign next_position_d.x = position.x;         // Stay at the current tile
    //assign next_position_d.y = position.y;         // y-coordinate remains the same
assign next_position_d[noc::kEastPort].x = (position.x + 1) % noc::kRingSize;
assign next_position_d[noc::kWestPort].x = (position.x + noc::kRingSize - 1) % noc::kRingSize;

    always_ff @(posedge clk) begin
        next_position_q <= next_position_d;
    end

    always_comb begin
        // Routing decision based on current direction (East, West, or Local)
        unique case (current_routing)
            noc::goEast: next_routing = routing(next_position_q[noc::kEastPort], destination, current_routing); // Clockwise (East)
            noc::goWest: next_routing = routing(next_position_q[noc::kWestPort], destination, current_routing); // Counter-clockwise (West)
          //  noc::goLocal: next_routing = noc::goLocal;  // Stay at local port (no movement)
            default: next_routing = current_routing;  // Default to local if nothing else
        endcase
    end

endmodule

