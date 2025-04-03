// 4 inputs to 1 output router arbiter
//
// There is no delay from request to grant.
// The abriter assumes that the request remains stable while the entire
// packet is forwarded. Hence, priority is updated whenever a tail flit
// is forwarded. Grant is locked between a head flit and the corresponding
// tail flit.
//
// Interface
//
// * Inputs
// - clk: clock.
// - rst: active-high reset.
// - request: each bit should be set to 1 if there is a valid flit coming from the corresponding
//   input port that needs to be routed to the output port arbitrated by this module.
// - forwarding_head: set to 1 to indicate the head flit of a new packet is being routed this cycle.
//   The current grant gets locked until the tail flit is forwarded (wormhole routing)
// - forwarding_tail: set to 1 to indicate the tail flit of a packet is being routed this cycle.
//   Priority is updated and grant is unlocked.
//
// * Outputs
// - grant: one-hot or zero. When grant[i] is set, request[i] is granted and the packet from the
//   corresponding input port i can be routed.
//   and the packet from the input
// - grant_valid: this flag indicates whether the current grant output is valid. When at least one
//   request bit is set, the arbiter grants the next higher priority request with zero-cycles delay,
//   unless grant is locked.
//

module router_arbiter (
    input  logic clk,
    input  logic rst,
    input  logic [1:0] request,
    input  logic forwarding_head,
    input  logic forwarding_tail,
    output logic [1:0] grant,
    output logic grant_valid
);

    logic grant_locked;

    // Lock current grant for flit between head and tail, tail included
    always_ff @(posedge clk) begin
        if (rst) begin
            grant_locked <= 1'b0;
        end else begin
            if (forwarding_tail) begin
                grant_locked <= 1'b0;
            end else if (forwarding_head) begin
                grant_locked <= 1'b1;
            end
        end
    end

    assign grant_valid = |request & ~grant_locked;

    // Update priority
    typedef logic [1:0][1:0] priority_t;
    priority_t priority_mask, priority_mask_next;
    priority_t grant_stage1;
    logic [1:0]grant_stage2;

    // Higher priority is given to request[0] at reset
    localparam priority_t InitialPriority = {
        2'b00,  
        2'b10  
        //4'b1100,  // request[1]
        //4'b1110
    };  // request[0]

    always_ff @(posedge clk) begin
        if (rst) begin
            priority_mask <= InitialPriority;
        end else if (forwarding_head) begin
            priority_mask <= priority_mask_next;
        end
    end

    always_comb begin
        priority_mask_next = priority_mask;

        unique case (grant)
            2'b01: begin
                priority_mask_next[0]    = '0;
                priority_mask_next[1][0] = 1'b1;
                
            end
            2'b10: begin
                priority_mask_next[1]    = '0;
                priority_mask_next[0][1] = 1'b1;
                
            end
            
            default begin
            end
        endcase
    end

    genvar g_i, g_j;
    for (g_i = 0; g_i < 2; g_i++) begin : gen_grant

        for (g_j = 0; g_j < 2; g_j++) begin : gen_grant_stage1
            assign grant_stage1[g_i][g_j] = request[g_j] & priority_mask[g_j][g_i];
        end

		 assign grant_stage2[g_i] = ~(grant_stage1[g_i][0] | grant_stage1[g_i][1]);     

        assign grant[g_i] = &grant_stage2[g_i] & request[g_i];

    end  // gen_grant

//	assign grant_stage2 = ~(grant_stage1[0] | grant_stage1[1]);

    //
    // Assertions
    //

`ifndef SYNTHESIS
    // pragma coverage off
    //VCS coverage off

    a_grant_onehot :
    assert property (@(posedge clk) disable iff (rst) $onehot0(grant))
    else $error("Fail: a_grant_onehot");

    // pragma coverage on
    //VCS coverage on
`endif  // ~SYNTHESIS

endmodule
