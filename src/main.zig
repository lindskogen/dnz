const std = @import("std");

const DnsFlags = packed struct(u16) { qr: u1, opcode: u4, aa: u1, tc: u1, rd: u1, ra: u1, z: u3, rcode: u4 };

const DnsMessage = extern struct {
    // ID
    packet_identifier: u16,
    flags: DnsFlags,
    // QDCOUNT
    number_questions: u16,
    // ANCOUNT
    number_answers: u16,
    // NSCOUNT
    number_authority_rrs: u16,
    // ARCOUNT
    number_additional_rrs: u16,
};

pub fn main() !void {
    const networkEndianness: std.builtin.Endian = .big;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const socket = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
    defer std.posix.close(socket);

    const addr = try std.net.Address.parseIp("0.0.0.0", 2053);

    try std.posix.bind(socket, &addr.any, addr.getOsSockLen());

    var buf: [512]u8 = undefined;
    var resp_buf: [512]u8 = undefined;
    var read_stream = std.io.fixedBufferStream(&buf);
    var reader = read_stream.reader();

    var write_stream = std.io.fixedBufferStream(&resp_buf);
    var writer = write_stream.writer();

    var src_addr: std.posix.sockaddr = undefined;
    var src_len: std.posix.socklen_t = undefined;

    while (true) {
        try write_stream.seekBy(12); // skip header
        _ = try std.posix.recvfrom(socket, &buf, 0, &src_addr, &src_len);
        // std.debug.assert(len == @sizeOf(DnsMessage));
        var msg = try reader.readStructEndian(DnsMessage, networkEndianness);

        var questions = std.ArrayList([][]u8).init(allocator);
        for (0..msg.number_questions) |_| {
            var labels = std.ArrayList([]u8).init(allocator);
            var label_len = try reader.readInt(u8, networkEndianness);
            while (label_len > 0) {
                const label_buf = try allocator.alloc(u8, label_len);
                _ = try reader.read(label_buf);
                try labels.append(label_buf);
                label_len = try reader.readInt(u8, networkEndianness);
            }
            const q_type = try reader.readInt(u16, networkEndianness);
            const q_class = try reader.readInt(u16, networkEndianness);

            std.debug.print("Q: ", .{});
            for (labels.items) |label| {
                std.debug.print("{s}.", .{label});
            }
            std.debug.print(" {d} {d} \n", .{ q_type, q_class });

            try questions.append(try labels.toOwnedSlice());
        }

        // Write question section
        for (questions.items) |q| {
            for (q) |label| {
                try writer.writeInt(u8, @intCast(label.len), networkEndianness);
                _ = try writer.write(label);
            }
            try writer.writeInt(u8, 0, networkEndianness);

            try writer.writeInt(u16, 1, networkEndianness);
            try writer.writeInt(u16, 1, networkEndianness);
        }

        // Write answer section
        for (questions.items) |q| {
            for (q) |label| {
                try writer.writeInt(u8, @intCast(label.len), networkEndianness);
                _ = try writer.write(label);
            }
            try writer.writeInt(u8, 0, networkEndianness);

            try writer.writeInt(u16, 1, networkEndianness);
            try writer.writeInt(u16, 1, networkEndianness);

            const ttl: u32 = 1;
            try writer.writeInt(u32, ttl, networkEndianness);

            const rdata = [4]u8{ 0x08, 0x08, 0x08, 0x08 };

            try writer.writeInt(u16, @sizeOf(@TypeOf(rdata)), networkEndianness);

            try writer.writeAll(&rdata);
        }

        std.debug.print("Recv: '{any}'\n", .{msg});

        msg.flags.qr = 1;
        msg.number_questions = @intCast(questions.items.len);
        msg.number_answers = @intCast(questions.items.len);

        std.debug.print("Send: '{any}'\n", .{msg});

        var headerStream = std.io.fixedBufferStream(&resp_buf);
        try headerStream.writer().writeStructEndian(msg, networkEndianness);

        std.debug.print("write: {d}\n", .{write_stream.pos});

        _ = try std.posix.sendto(socket, write_stream.getWritten(), 0, &src_addr, src_len);

        read_stream.reset();
        write_stream.reset();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
