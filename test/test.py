# SPDX-FileCopyrightText: © 2026 Tiny Tapeout, Hirosh Dabui <hirosh@dabui.de>
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.types import LogicArray
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge
from cocotbext.uart import UartSource, UartSink


async def spi_slave(dut, clock, cs, mosi, miso):
    """A simple SPI slave that captures 32 MOSI bits and echoes MOSI back on MISO."""
    miso.value = 0
    out_buff = LogicArray("0" * 32)

    await FallingEdge(cs)

    for bit_index in range(32):
        await RisingEdge(clock)
        mosi_val = mosi.value
        out_buff[31 - bit_index] = mosi_val

        await FallingEdge(clock)
        miso.value = mosi_val

    received = out_buff.to_unsigned()
    assert received == 0xDEADBEAF, f"Expected 0xDEADBEAF, got {received:#010X}"
    dut._log.info(f"SPI slave received expected value: 0x{received:08X}")


async def boot_dut(dut, test_sel):
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    dut.test_sel.value = test_sel
    dut.spi_sio1_so_miso0.value = 0
    dut.uart_rx.value = 1
    dut.ena.value = 1

    cocotb.start_soon(
        spi_slave(
            dut,
            dut.spi_sclk0,
            dut.spi_cen0,
            dut.spi_sio0_si_mosi0,
            dut.spi_sio1_so_miso0,
        )
    )

    uart_source = UartSource(dut.uart_rx, baud=115200, bits=8)
    uart_sink = UartSink(dut.uart_tx, baud=115200, bits=8)

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    return uart_source, uart_sink


async def uart_read_some(dut, uart_sink, cycles=10000):
    await ClockCycles(dut.clk, cycles)
    count = uart_sink.count()
    if count == 0:
        return b""
    data = bytes(uart_sink.read_nowait(count))
    dut._log.info(f"UART chunk: {data!r}")
    return data


async def uart_wait_for_prefix(dut, uart_sink, prefix: bytes, max_rounds=20, round_cycles=50000):
    collected = bytearray()
    for _ in range(max_rounds):
        collected.extend(await uart_read_some(dut, uart_sink, round_cycles))
        if len(collected) >= len(prefix):
            break

    data = bytes(collected[:len(prefix)])
    dut._log.info(f"UART prefix data: {data!r}")
    assert data == prefix, f"Expected prefix {prefix!r}, got {data!r}"
    return bytes(collected)


async def uart_wait_for_token(dut, uart_sink, token: bytes, max_rounds=200, round_cycles=10000, initial=b""):
    collected = bytearray(initial)
    for _ in range(max_rounds):
        if token in collected:
            return bytes(collected)
        collected.extend(await uart_read_some(dut, uart_sink, round_cycles))
    raise AssertionError(f"Did not see token {token!r}. Collected: {bytes(collected)!r}")


@cocotb.test()
async def test_boot_uart_psram(dut):
    dut._log.info("start")
    uart_source, uart_sink = await boot_dut(dut, test_sel=0)

    collected = await uart_wait_for_prefix(
        dut,
        uart_sink,
        b"Hello UART\n",
        max_rounds=10,
        round_cycles=50000,
    )

    collected = await uart_wait_for_token(
        dut,
        uart_sink,
        b"RAM-HI OK\n",
        max_rounds=300,
        round_cycles=10000,
        initial=collected,
    )

    print("\n=== Full UART output ===")
    print(collected.decode(errors="replace"))
    print("=== End UART output ===\n")

    expected_tokens = [
        b"RAM-HI START\n",
        b"PSRAM0 OK\n",
        b"PSRAM1 OK\n",
        b"PSRAM2 OK\n",
        b"PSRAM3 OK\n",
        b"RAM-HI OK\n",
    ]

    for token in expected_tokens:
        assert token in collected, f"Missing token {token!r} in UART output: {collected!r}"

    forbidden_tokens = [
        b"RAM-HI FAIL",
        b"ALIAS FAIL",
        b"OFFSET FAIL",
    ]

    for token in forbidden_tokens:
        assert token not in collected, f"Unexpected token {token!r} in UART output: {collected!r}"

    await uart_source.write(b"K")
    await ClockCycles(dut.clk, 2500)
    await uart_source.write(b"I")
    await ClockCycles(dut.clk, 2500)
    await uart_source.write(b"A")
    await ClockCycles(dut.clk, 2500)
    await uart_source.write(b"N")
    await ClockCycles(dut.clk, 2500)
    await uart_source.write(b"V")
    await ClockCycles(dut.clk, 4000)

    data = uart_sink.read_nowait(5)
    dut._log.info(f"UART echo data: {data}")
    assert data == b"kianv"


@cocotb.test()
async def test_gpio(dut):
    """Test single-bit GPIO output on uo_out[1]."""
    dut._log.info("start")
    await boot_dut(dut, test_sel=1)

    gpio_pin = dut.gpio_out

    await RisingEdge(gpio_pin)
    dut._log.info("GPIO: first rising edge (start marker)")

    for i, expected in enumerate([0, 1, 0, 1]):
        await gpio_pin.value_change
        try:
            val = int(gpio_pin.value)
        except ValueError:
            val = -1
        dut._log.info(f"GPIO transition {i}: got {val} (expected {expected})")
        assert val == expected, f"GPIO step {i}: expected {expected}, got {val}"

    dut._log.info("GPIO test passed")
