import os

from aiohttp import web
from aiohttp.test_utils import AioHTTPTestCase, unittest_run_loop

from meross_iot.controller.mixins.spray import SprayMixin
from meross_iot.manager import MerossManager
from meross_iot.model.enums import OnlineStatus, SprayMode
from tests import async_get_client

if os.name == 'nt':
    import asyncio
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
else:
    import asyncio


class TestSpray(AioHTTPTestCase):
    async def get_application(self):
        return web.Application()

    async def setUpAsync(self):
        # Wait some time before next test-burst
        await asyncio.sleep(10)
        self.meross_client, self.requires_logout = await async_get_client()

        # Look for a device to be used for this test
        self.meross_manager = MerossManager(http_client=self.meross_client)
        await self.meross_manager.async_init()
        devices = await self.meross_manager.async_device_discovery()
        self.test_devices = self.meross_manager.find_devices(device_class=SprayMixin, online_status=OnlineStatus.ONLINE)

    @unittest_run_loop
    async def test_spry(self):
        if len(self.test_devices) < 1:
            self.skipTest("Could not find any SprayMixin within the given set of devices. "
                          "The test will be skipped")

        dev = self.test_devices[0]
        await dev.async_set_mode(mode=SprayMode.CONTINUOUS)
        self.assertEqual(dev.get_current_mode(), SprayMode.CONTINUOUS)

        await dev.async_set_mode(mode=SprayMode.INTERMITTENT)
        self.assertEqual(dev.get_current_mode(), SprayMode.INTERMITTENT)

        await dev.async_set_mode(mode=SprayMode.OFF)
        self.assertEqual(dev.get_current_mode(), SprayMode.OFF)

        await dev.async_update()

    """
    @unittest_run_loop
    async def test_rgb_push_notification(self):
        # Make sure we have an RGB-capable available device
        rgb_capable = list(filter(lambda d: d.supports_rgb, self.light_devices))
        if len(rgb_capable) < 1:
            self.skipTest("Could not find any RGB-capable LightMixin within the given set of devices. "
                          "The test will be skipped")
            return

        light = rgb_capable[0]

        # Create a new manager
        new_meross_client = await MerossHttpClient.async_from_user_password(email=EMAIL, password=PASSWORD)
        m = None
        try:
            # Retrieve the same device with another manager
            m = MerossManager(http_client=new_meross_client)
            await m.async_init()
            await m.async_device_discovery()
            devs = m.find_device(uuids=(light.uuid))
            dev = devs[0]

            # Set RGB color to known state
            r = await light.async_set_light_color(rgb=(255, 0, 0))
            await asyncio.sleep(2)

            # Turn on the device
            r = await light.async_set_light_color(rgb=(0, 255, 0))

            # Wait a bit and make sure the other manager received the push notification
            await asyncio.sleep(10)
            self.assertEqual(light.rgb_color, (0, 255, 0))
            self.assertEqual(dev.rgb_color, (0, 255, 0))
        finally:
            if m is not None:
                m.close()
            await new_meross_client.async_logout()
    """

    async def tearDownAsync(self):
        if self.requires_logout:
            await self.meross_client.async_logout()
        self.meross_manager.close()

        # Give a change to asyncio clean everything up
        await asyncio.sleep(1)