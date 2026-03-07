# SPDX-FileCopyrightText: © 2026 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.types import LogicArray
from cocotb.triggers import ClockCycles
from cocotbext.uart import UartSource, UartSink
from cocotb.triggers import RisingEdge, FallingEdge


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


@cocotb.test()
async def test_uart(dut):
    dut._log.info("start")
    dut.test_sel.value = 0
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
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

    # Wait for firmware to boot, run SPI test, and print "Hello UART\n"
    for i in range(5):
        await ClockCycles(dut.clk, 100000)
        if uart_sink.count() >= 11:
            break

    expected_str = b"Hello UART\n"
    available = uart_sink.count()
    dut._log.info(f"UART bytes available: {available}")
    data = uart_sink.read_nowait(min(available, len(expected_str)))
    dut._log.info(f"UART Data: {data}")
    assert data == expected_str, f"Expected {expected_str!r}, got {data!r} ({available} bytes avail)"

    # The firmware converts uppercase to lowercase and echoes
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
    dut._log.info(f"UART Data: {data}")
    assert data == b"kianv"


@cocotb.test()
async def test_gpio(dut):
    """Test single-bit GPIO output on uo_out[1]."""
    dut._log.info("start")
    dut.test_sel.value = 1  # firmware checks gpio_ui_in bit 0 (ui_in[1])
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    cocotb.start_soon(
        spi_slave(
            dut,
            dut.spi_sclk0,
            dut.spi_cen0,
            dut.spi_sio0_si_mosi0,
            dut.spi_sio1_so_miso0,
        )
    )

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # gpio_out is uo_out[1]; firmware toggles it: high, low, high, low, high
    gpio_pin = dut.gpio_out

    # Wait for first rising edge (start marker)
    await RisingEdge(gpio_pin)
    dut._log.info("GPIO: first rising edge (start marker)")

    # Expect: low, high, low, high (end marker)
    for i, expected in enumerate([0, 1, 0, 1]):
        await gpio_pin.value_change
        try:
            val = int(gpio_pin.value)
        except ValueError:
            val = -1
        dut._log.info(f"GPIO transition {i}: got {val} (expected {expected})")
        assert val == expected, f"GPIO step {i}: expected {expected}, got {val}"

    dut._log.info("GPIO test passed")
