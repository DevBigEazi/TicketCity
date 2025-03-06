import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Ticket_City", () => {
  async function deployAndSetupFixture() {
    const [
      owner,
      organizer,
      attendee1,
      attendee2,
      attendee3,
      attendee4,
      unregisteredAttendee,
    ] = await hre.ethers.getSigners();

    const TicketCity = await hre.ethers.getContractFactory("Ticket_City");
    const ticketCity = await TicketCity.deploy();
    await ticketCity.waitForDeployment();

    const currentTime = await time.latest();
    const startDate = currentTime + time.duration.days(1);
    const endDate = startDate + time.duration.days(7);

    const eventParams = {
      title: "Test Event",
      desc: "Test Description",
      imageUri: "ipfs://event-banner",
      location: "Test Location",
      startDate: startDate,
      endDate: endDate,
      expectedAttendees: 100,
      ticketType: 0, // FREE
    };

    const regularTicketFee = hre.ethers.parseEther("0.1");
    const vipTicketFee = hre.ethers.parseEther("0.15");

    return {
      ticketCity,
      owner,
      organizer,
      attendee1,
      attendee2,
      attendee3,
      attendee4,
      unregisteredAttendee,
      eventParams,
      currentTime,
      regularTicketFee,
      vipTicketFee,
    };
  }

  describe("Deployment", () => {
    it("Should set the right owner", async () => {
      const { ticketCity, owner } = await loadFixture(deployAndSetupFixture);
      expect(await ticketCity.owner()).to.equal(owner.address);
    });

    it("Should initialize counters to zero", async () => {
      const { ticketCity } = await loadFixture(deployAndSetupFixture);
      expect(await ticketCity.totalEventOrganised()).to.equal(0);
      expect(await ticketCity.totalTicketCreated()).to.equal(0);
      expect(await ticketCity.totalPurchasedTicket()).to.equal(0);
    });
  });

  describe("Event Organization", () => {
    it("Should revert when creating event with empty title or description", async () => {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      await expect(
        ticketCity.connect(organizer).createEvent(
          "", // empty title
          eventParams.desc,
          eventParams.imageUri,
          eventParams.location,
          eventParams.startDate,
          eventParams.endDate,
          eventParams.expectedAttendees,
          eventParams.ticketType
        )
      ).to.be.revertedWithCustomError(ticketCity, "EmptyTitleOrDescription");
    });

    it("Should create a free event successfully", async () => {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      await expect(
        ticketCity
          .connect(organizer)
          .createEvent(
            eventParams.title,
            eventParams.desc,
            eventParams.imageUri,
            eventParams.location,
            eventParams.startDate,
            eventParams.endDate,
            eventParams.expectedAttendees,
            eventParams.ticketType
          )
      )
        .to.emit(ticketCity, "EventOrganized")
        .withArgs(organizer.address, 1, eventParams.ticketType);

      expect(await ticketCity.totalEventOrganised()).to.equal(1);
    });

    it("Should revert when creating event with invalid dates", async () => {
      const { ticketCity, organizer, eventParams, currentTime } =
        await loadFixture(deployAndSetupFixture);

      const invalidStartDate = currentTime - time.duration.days(1); // Past date

      await expect(
        ticketCity
          .connect(organizer)
          .createEvent(
            eventParams.title,
            eventParams.desc,
            eventParams.imageUri,
            eventParams.location,
            invalidStartDate,
            eventParams.endDate,
            eventParams.expectedAttendees,
            eventParams.ticketType
          )
      ).to.be.revertedWithCustomError(ticketCity, "InvalidDates");
    });

    it("Should revert with zero expected attendees", async () => {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      await expect(
        ticketCity.connect(organizer).createEvent(
          eventParams.title,
          eventParams.desc,
          eventParams.imageUri,
          eventParams.location,
          eventParams.startDate,
          eventParams.endDate,
          0, // Invalid expected attendees
          eventParams.ticketType
        )
      ).to.be.revertedWithCustomError(ticketCity, "ExpectedAttendeesIsTooLow");
    });
  });

  describe("Ticket Creation and Purchase", () => {
    it("Should mint free ticket", async () => {
      const { ticketCity, organizer, attendee1, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create event
      await ticketCity
        .connect(organizer)
        .createEvent(
          eventParams.title,
          eventParams.desc,
          eventParams.imageUri,
          eventParams.location,
          eventParams.startDate,
          eventParams.endDate,
          eventParams.expectedAttendees,
          eventParams.ticketType
        );

      expect(
        await ticketCity.connect(organizer).createTicket(
          1, // eventId
          0, // NONE category
          0,
          "ipfs://regular-ticket"
        )
      )
        .to.emit(ticketCity, "TicketCreated")
        .withArgs(1, organizer.address, anyValue, 0, "REGULAR");
      // Purchase ticket
      await expect(
        ticketCity.connect(attendee1).purchaseTicket(
          1, // eventId
          0 // NONE category for free tickets
        )
      )
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee1.address, 0);
    });

    it("Should revert when creating free ticket for paid event", async () => {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      // Create paid event
      const paidEventParams = { ...eventParams, ticketType: 1 }; // PAID
      await ticketCity
        .connect(organizer)
        .createEvent(
          paidEventParams.title,
          paidEventParams.desc,
          paidEventParams.imageUri,
          paidEventParams.location,
          paidEventParams.startDate,
          paidEventParams.endDate,
          paidEventParams.expectedAttendees,
          paidEventParams.ticketType
        );

      // Try to create free ticket
      await expect(
        ticketCity
          .connect(organizer)
          .createTicket(1, 0, 0, "ipfs://free-ticket") // NONE category
      ).to.be.revertedWithCustomError(ticketCity, "FreeTicketForFreeEventOnly");
    });

    // Test for invalid ticket fee
    it("Should revert when creating paid ticket with zero fee", async () => {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      // Create paid event
      const paidEventParams = { ...eventParams, ticketType: 1 }; // PAID
      await ticketCity
        .connect(organizer)
        .createEvent(
          paidEventParams.title,
          paidEventParams.desc,
          paidEventParams.imageUri,
          paidEventParams.location,
          paidEventParams.startDate,
          paidEventParams.endDate,
          paidEventParams.expectedAttendees,
          paidEventParams.ticketType
        );

      await expect(
        ticketCity
          .connect(organizer)
          .createTicket(1, 1, 0, "ipfs://regular-ticket") // zero fee
      ).to.be.revertedWithCustomError(ticketCity, "InvalidTicketFee");
    });

    it("Should create and purchase paid tickets", async () => {
      const { ticketCity, organizer, attendee1, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Log initial balance
      const initialBalance = await hre.ethers.provider.getBalance(
        attendee1.address
      );
      console.log(
        "Initial attendee1 balance:",
        hre.ethers.formatEther(initialBalance),
        "ETH"
      );

      // Create paid event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID ticket type
      );

      // Create regular ticket
      const regularTicketFee = hre.ethers.parseEther("0.1");
      //   uint256 _eventId,
      //   Types.PaidTicketCategory _category,
      //   uint256 _ticketFee,
      //   string memory _ticketUri
      expect(
        await ticketCity.connect(organizer).createTicket(
          1, // eventId
          1, // REGULAR category
          regularTicketFee,
          "ipfs://regular-ticket"
        )
      )
        .to.emit(ticketCity, "TicketCreated")
        .withArgs(1, organizer.address, anyValue, regularTicketFee, "REGULAR");

      // Purchase ticket
      expect(
        await ticketCity.connect(attendee1).purchaseTicket(
          1, // eventId
          1, // REGULAR category
          { value: regularTicketFee }
        )
      )
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee1.address, regularTicketFee);

      // Verify the purchase
      const eventDetails = await ticketCity.events(1);
      expect(eventDetails.userRegCount).to.equal(1);

      // confirm NFTticket
      const ticketDetails = await ticketCity.eventTickets(1);
      console.log(
        "Regular Ticket NFT Address:",
        ticketDetails.regularTicketNFT
      );
    });

    it("Should fail to purchase paid ticket with incorrect payment", async () => {
      const { ticketCity, organizer, attendee1, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create paid event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID ticket type
      );

      // Create regular ticket
      const regularTicketFee = hre.ethers.parseEther("0.1");
      await ticketCity.connect(organizer).createTicket(
        1, // eventId
        1, // REGULAR category
        regularTicketFee,
        "ipfs://regular-ticket"
      );

      // Try to purchase with incorrect fee
      const incorrectFee = hre.ethers.parseEther("0.05");
      await expect(
        ticketCity.connect(attendee1).purchaseTicket(
          1,
          1, // REGULAR category
          { value: incorrectFee }
        )
      ).to.be.revertedWith("Incorrect payment amount");
    });

    it("Should fail to purchase non-existent ticket category", async () => {
      const { ticketCity, organizer, attendee1, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create paid event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID ticket type
      );

      // Try to purchase VIP ticket when only REGULAR exists
      const ticketFee = hre.ethers.parseEther("0.1");
      await ticketCity
        .connect(organizer)
        .createTicket(1, 1, ticketFee, "ipfs://regular-ticket");

      await expect(
        ticketCity.connect(attendee1).purchaseTicket(
          1,
          2, // VIP category
          { value: ticketFee }
        )
      ).to.be.revertedWith("VIP tickets not available");
    });
  });

  describe("Ticket Purchase In Batches", function () {
    it("Should purchase multiple Regular tickets successfully", async function () {
      const {
        ticketCity,
        organizer,
        attendee1,
        attendee2,
        attendee3,
        eventParams,
      } = await loadFixture(deployAndSetupFixture);

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create Regular Tickets
      const regularTicketFee = hre.ethers.parseEther("0.1");

      await ticketCity.connect(organizer).createTicket(
        1, // Event ID
        1, // Regular
        regularTicketFee,
        "ipfs://regular-ticket"
      );

      // Purchase Multiple Regular Tickets
      const recipients = [
        attendee1.address,
        attendee2.address,
        attendee3.address,
      ];
      const totalFee = regularTicketFee * BigInt(recipients.length);

      await expect(
        ticketCity
          .connect(organizer)
          .purchaseMultipleTickets(1, 1, recipients, { value: totalFee }) // 1 = Regular
      )
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee1.address, regularTicketFee)
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee2.address, regularTicketFee)
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee3.address, regularTicketFee);

      // Verify Registration
      for (const recipient of recipients) {
        expect(await ticketCity.hasRegistered(recipient, 1)).to.be.true;
      }
    });

    it("Should purchase multiple VIP tickets successfully", async function () {
      const { ticketCity, organizer, attendee1, attendee2, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create VIP Tickets
      const vipTicketFee = hre.ethers.parseEther("0.5");

      await ticketCity.connect(organizer).createTicket(
        1, // Event ID
        2, // VIP
        vipTicketFee,
        "ipfs://vip-ticket"
      );

      // Purchase Multiple VIP Tickets
      const recipients = [attendee1.address, attendee2.address];
      const totalFee = vipTicketFee * BigInt(recipients.length);

      await expect(
        ticketCity
          .connect(organizer)
          .purchaseMultipleTickets(1, 2, recipients, { value: totalFee }) // 2 = VIP
      )
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee1.address, vipTicketFee)
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee2.address, vipTicketFee);

      // Verify Registration
      for (const recipient of recipients) {
        expect(await ticketCity.hasRegistered(recipient, 1)).to.be.true;
      }
    });

    it("Should revert if incorrect payment amount is sent", async function () {
      const { ticketCity, organizer, attendee1, attendee2, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create Regular Tickets
      const regularTicketFee = hre.ethers.parseEther("0.1");

      await ticketCity.connect(organizer).createTicket(
        1, // Event ID
        1,
        regularTicketFee,
        "ipfs://regular-ticket"
      );

      // Send incorrect payment
      const recipients = [attendee1.address, attendee2.address];
      const incorrectFee = regularTicketFee * BigInt(recipients.length - 1);

      await expect(
        ticketCity
          .connect(organizer)
          .purchaseMultipleTickets(1, 1, recipients, { value: incorrectFee }) // 1 = Regular
      ).to.be.revertedWith("Incorrect total payment amount");
    });

    it("Should revert if empty recipient list is provided", async function () {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      await expect(
        ticketCity
          .connect(organizer)
          .purchaseMultipleTickets(1, 1, [], { value: 0 }) // Empty array
      ).to.be.revertedWith("Empty recipients list");
    });

    it("Should revert if event has ended", async function () {
      const { ticketCity, organizer, attendee1, attendee2, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Move time beyond the event end date
      await time.increaseTo(eventParams.endDate + 1);

      const recipients = [attendee1.address, attendee2.address];

      await expect(
        ticketCity
          .connect(organizer)
          .purchaseMultipleTickets(1, 1, recipients, { value: 0 })
      ).to.be.revertedWithCustomError(ticketCity, "EventHasEnded");
    });

    it("Should revert if ticket purchase exceeds expected attendees limit", async function () {
      const {
        ticketCity,
        organizer,
        attendee1,
        attendee2,
        attendee3,
        attendee4,
        eventParams,
      } = await loadFixture(deployAndSetupFixture);

      // Set a small attendee limit
      eventParams.expectedAttendees = 3;

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create Regular Tickets
      const regularTicketFee = hre.ethers.parseEther("0.1");

      await ticketCity.connect(organizer).createTicket(
        1, // Event ID
        1, // REGULAR
        regularTicketFee,
        "ipfs://regular-ticket"
      );

      // Attempt to register more than expected attendees
      const recipients = [
        attendee1.address,
        attendee2.address,
        attendee3.address,
        attendee4.address,
      ];
      const totalFee = regularTicketFee * BigInt(recipients.length);

      await expect(
        ticketCity
          .connect(organizer)
          .purchaseMultipleTickets(1, 1, recipients, { value: totalFee })
      ).to.be.revertedWithCustomError(ticketCity, "RegistrationHasClosed");
    });
  });

  describe("Attendance Verification", () => {
    it("Should verify attendance for valid free ticket holder", async () => {
      const { ticketCity, organizer, attendee1, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create and setup event
      await ticketCity
        .connect(organizer)
        .createEvent(
          eventParams.title,
          eventParams.desc,
          eventParams.imageUri,
          eventParams.location,
          eventParams.startDate,
          eventParams.endDate,
          eventParams.expectedAttendees,
          eventParams.ticketType
        );

      // Create Free Ticket
      await ticketCity
        .connect(organizer)
        .createTicket(1, 0, 0, "ipfs://test-uri");

      // Log the Free Ticket NFT Address
      const eventDetails = await ticketCity.events(1);
      console.log("Free Ticket NFT Address:", eventDetails.ticketNFTAddr);

      // Purchase Free Ticket
      await ticketCity.connect(attendee1).purchaseTicket(1, 0);

      // Move time to event start date
      await time.increaseTo(eventParams.startDate);

      // Verify attendance
      await expect(ticketCity.connect(attendee1).verifyAttendance(1))
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee1.address, anyValue);
    });

    it("Should verify attendance for Regular and VIP ticket holders", async function () {
      const { ticketCity, organizer, attendee1, attendee2, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create a paid event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create Regular and VIP tickets
      const regularTicketFee = hre.ethers.parseEther("0.1");
      const vipTicketFee = hre.ethers.parseEther("0.5");

      await expect(
        ticketCity.connect(organizer).createTicket(
          1, // Event ID
          1, // REGULAR
          regularTicketFee,
          "ipfs://regular-ticket"
        )
      )
        .to.emit(ticketCity, "TicketCreated")
        .withArgs(1, organizer.address, anyValue, regularTicketFee, "REGULAR");

      await expect(
        ticketCity.connect(organizer).createTicket(
          1, // Event ID
          2, // VIP
          vipTicketFee,
          "ipfs://vip-ticket"
        )
      )
        .to.emit(ticketCity, "TicketCreated")
        .withArgs(1, organizer.address, anyValue, vipTicketFee, "VIP");

      // Purchase Regular and VIP tickets
      await expect(
        ticketCity
          .connect(attendee1)
          .purchaseTicket(1, 1, { value: regularTicketFee }) // 1 = Regular
      )
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee1.address, regularTicketFee);

      await expect(
        ticketCity
          .connect(attendee2)
          .purchaseTicket(1, 2, { value: vipTicketFee }) // 2 = VIP
      )
        .to.emit(ticketCity, "TicketPurchased")
        .withArgs(1, attendee2.address, vipTicketFee);

      // Ensure tickets were assigned
      const regularBalance = await ticketCity.eventTickets(1);
      console.log("Regular Ticket NFT:", regularBalance.regularTicketNFT);

      const vipBalance = await ticketCity.eventTickets(1);
      console.log("VIP Ticket NFT:", vipBalance.vipTicketNFT);

      // Move time to event start
      await time.increaseTo(eventParams.startDate);

      // Verify Attendance for Regular Ticket Holder
      await expect(ticketCity.connect(attendee1).verifyAttendance(1))
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee1.address, anyValue);

      // Verify Attendance for VIP Ticket Holder
      await expect(ticketCity.connect(attendee2).verifyAttendance(1))
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee2.address, anyValue);
    });
  });

  describe("Group Attendance Verification", function () {
    it("Should verify attendance for multiple Regular ticket holders", async function () {
      const {
        ticketCity,
        organizer,
        attendee1,
        attendee2,
        attendee3,
        eventParams,
      } = await loadFixture(deployAndSetupFixture);

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create Regular Tickets
      const regularTicketFee = hre.ethers.parseEther("0.1");

      await ticketCity.connect(organizer).createTicket(
        1, // Event ID
        1, // REGULAR
        regularTicketFee,
        "ipfs://regular-ticket"
      );

      // Purchase Regular Tickets
      const recipients = [
        attendee1.address,
        attendee2.address,
        attendee3.address,
      ];
      const totalFee = regularTicketFee * BigInt(recipients.length);

      await ticketCity
        .connect(organizer)
        .purchaseMultipleTickets(1, 1, recipients, { value: totalFee }); // 1 = Regular

      // Move time to event start
      await time.increaseTo(eventParams.startDate);

      // Verify attendance for multiple attendees
      await expect(
        ticketCity.connect(organizer).verifyGroupAttendance(1, recipients)
      )
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee1.address, anyValue)
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee2.address, anyValue)
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee3.address, anyValue);

      // Ensure all attendees are marked as verified
      for (const recipient of recipients) {
        expect(await ticketCity.isVerified(recipient, 1)).to.be.true;
      }
    });

    it("Should verify attendance for multiple VIP ticket holders", async function () {
      const { ticketCity, organizer, attendee1, attendee2, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create VIP Tickets
      const vipTicketFee = hre.ethers.parseEther("0.5");

      await ticketCity.connect(organizer).createTicket(
        1, // Event ID
        2,
        vipTicketFee,
        "ipfs://vip-ticket"
      );

      // Purchase VIP Tickets
      const recipients = [attendee1.address, attendee2.address];
      const totalFee = vipTicketFee * BigInt(recipients.length);

      await ticketCity
        .connect(organizer)
        .purchaseMultipleTickets(1, 2, recipients, { value: totalFee }); // 2 = VIP

      // Move time to event start
      await time.increaseTo(eventParams.startDate);

      // Verify attendance for multiple attendees
      await expect(
        ticketCity.connect(organizer).verifyGroupAttendance(1, recipients)
      )
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee1.address, anyValue)
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee2.address, anyValue);

      // Ensure all attendees are marked as verified
      for (const recipient of recipients) {
        expect(await ticketCity.isVerified(recipient, 1)).to.be.true;
      }
    });

    it("Should skip already verified attendees", async function () {
      const { ticketCity, organizer, attendee1, attendee2, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create Regular Tickets
      const regularTicketFee = hre.ethers.parseEther("0.1");

      await ticketCity.connect(organizer).createTicket(
        1, // Event ID,
        1, // REGULAR
        regularTicketFee,
        "ipfs://regular-ticket"
      );

      // Purchase Regular Tickets
      const recipients = [attendee1.address, attendee2.address];
      const totalFee = regularTicketFee * BigInt(recipients.length);

      await ticketCity
        .connect(organizer)
        .purchaseMultipleTickets(1, 1, recipients, { value: totalFee }); // 1 = Regular

      // Move time to event start
      await time.increaseTo(eventParams.startDate);

      // Verify attendance for attendee1 first
      await ticketCity.connect(attendee1).verifyAttendance(1);

      // Attempt group verification again
      await expect(
        ticketCity.connect(organizer).verifyGroupAttendance(1, recipients)
      )
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee2.address, anyValue);

      // Ensure both attendees are verified in the end
      expect(await ticketCity.isVerified(attendee1.address, 1)).to.be.true;
      expect(await ticketCity.isVerified(attendee2.address, 1)).to.be.true;
    });

    it("Should revert if empty attendees list is provided", async function () {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Move time to event start
      await time.increaseTo(eventParams.startDate);

      // Attempt to verify with empty list
      await expect(
        ticketCity.connect(organizer).verifyGroupAttendance(1, [])
      ).to.be.revertedWithCustomError(ticketCity, "EmptyAttendeesList");
    });

    it("Should skip unregistered attendees", async function () {
      const {
        ticketCity,
        organizer,
        attendee1,
        attendee2,
        unregisteredAttendee,
        eventParams,
      } = await loadFixture(deployAndSetupFixture);

      // Create an event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // 1 = Paid event
      );

      // Create Regular Tickets
      const regularTicketFee = hre.ethers.parseEther("0.1");

      await ticketCity.connect(organizer).createTicket(
        1, // Event ID
        1,
        regularTicketFee,
        "ipfs://regular-ticket"
      );

      // Purchase Regular Tickets
      const recipients = [attendee1.address, attendee2.address];
      const totalFee = regularTicketFee * BigInt(recipients.length);

      await ticketCity
        .connect(organizer)
        .purchaseMultipleTickets(1, 1, recipients, { value: totalFee }); // 1 = Regular

      // Move time to event start
      await time.increaseTo(eventParams.startDate);

      // Attempt group verification including an unregistered attendee
      await expect(
        ticketCity
          .connect(organizer)
          .verifyGroupAttendance(1, [
            attendee1.address,
            attendee2.address,
            unregisteredAttendee.address,
          ])
      )
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee1.address, anyValue)
        .to.emit(ticketCity, "AttendeeVerified")
        .withArgs(1, attendee2.address, anyValue);

      // Ensure only registered attendees are verified
      expect(await ticketCity.isVerified(attendee1.address, 1)).to.be.true;
      expect(await ticketCity.isVerified(attendee2.address, 1)).to.be.true;
      expect(await ticketCity.isVerified(unregisteredAttendee.address, 1)).to.be
        .false;
    });
  });

  describe("Revenue Management", () => {
    it("Should handle revenue release correctly", async () => {
      const { ticketCity, organizer, attendee1, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create paid event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );

      // Create and purchase regular ticket
      const ticketFee = hre.ethers.parseEther("0.1");
      await ticketCity
        .connect(organizer)
        .createTicket(1, 1, ticketFee, "ipfs://test-uri");
      await ticketCity
        .connect(attendee1)
        .purchaseTicket(1, 1, { value: ticketFee });

      // Move to event start and verify attendance
      await time.increaseTo(eventParams.startDate);
      await ticketCity.connect(attendee1).verifyAttendance(1);

      // Move past event end
      await time.increaseTo(eventParams.endDate + 1);

      // Check revenue release conditions
      const [canRelease, attendanceRate, revenue] =
        await ticketCity.canReleaseRevenue(1);
      expect(revenue).to.equal(ticketFee);
    });
  });

  describe("Getter Functions", function () {
    it("Should return specific event details", async function () {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      // Create an event
      await ticketCity
        .connect(organizer)
        .createEvent(
          eventParams.title,
          eventParams.desc,
          eventParams.imageUri,
          eventParams.location,
          eventParams.startDate,
          eventParams.endDate,
          eventParams.expectedAttendees,
          eventParams.ticketType
        );

      // Get event details - use array destructuring or direct access instead of object
      // Assuming the contract returns an array of values rather than an object
      const eventDetails = await ticketCity.events(1); // Try accessing storage directly

      // Verify event details
      expect(eventDetails.title).to.equal(eventParams.title);
      expect(eventDetails.desc).to.equal(eventParams.desc);
      expect(eventDetails.location).to.equal(eventParams.location);
      expect(eventDetails.startDate).to.equal(eventParams.startDate);
      expect(eventDetails.endDate).to.equal(eventParams.endDate);
      expect(eventDetails.expectedAttendees).to.equal(
        eventParams.expectedAttendees
      );
      expect(eventDetails.ticketType).to.equal(eventParams.ticketType);
      expect(eventDetails.organiser).to.equal(organizer.address);
    });

    it("Should return all events", async function () {
      const { ticketCity, organizer, attendee1, eventParams } =
        await loadFixture(deployAndSetupFixture);

      // Create first event
      await ticketCity.connect(organizer).createEvent(
        "Event 1",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );

      // Create second event
      await ticketCity.connect(attendee1).createEvent(
        "Event 2",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );

      // Get all events
      const allEvents = await ticketCity.getAllEvents();
      expect(allEvents.length).to.equal(2);
      expect(allEvents[0].title).to.equal("Event 1");
      expect(allEvents[1].title).to.equal("Event 2");
      expect(allEvents[0].organiser).to.equal(organizer.address);
      expect(allEvents[1].organiser).to.equal(attendee1.address);
    });

    it("Should return events without tickets by user", async function () {
      const { ticketCity, organizer, eventParams } = await loadFixture(
        deployAndSetupFixture
      );

      // Create free event without ticket
      await ticketCity.connect(organizer).createEvent(
        "Free Event No Ticket",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );

      // Create paid event without ticket
      await ticketCity.connect(organizer).createEvent(
        "Paid Event No Ticket",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );

      // Create event with ticket
      await ticketCity.connect(organizer).createEvent(
        "Event With Ticket",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );
      await ticketCity
        .connect(organizer)
        .createTicket(3, 0, 0, "ipfs://free-ticket");

      // Get events without tickets
      const eventsWithoutTickets =
        await ticketCity.getEventsWithoutTicketsByUser(organizer.address);
      expect(eventsWithoutTickets.length).to.equal(2);
      expect(eventsWithoutTickets[0]).to.equal(1);
      expect(eventsWithoutTickets[1]).to.equal(2);
    });

    it("Should return events with tickets by user", async function () {
      const { ticketCity, organizer, eventParams, regularTicketFee } =
        await loadFixture(deployAndSetupFixture);

      // Create free event with ticket
      await ticketCity.connect(organizer).createEvent(
        "Free Event With Ticket",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );
      await ticketCity
        .connect(organizer)
        .createTicket(1, 0, 0, "ipfs://free-ticket");

      // Create paid event with ticket
      await ticketCity.connect(organizer).createEvent(
        "Paid Event With Ticket",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );
      await ticketCity
        .connect(organizer)
        .createTicket(2, 1, regularTicketFee, "ipfs://regular-ticket");

      // Create event without ticket
      await ticketCity.connect(organizer).createEvent(
        "Event Without Ticket",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );

      // Get events with tickets
      const eventsWithTickets = await ticketCity.getEventsWithTicketByUser(
        organizer.address
      );
      expect(eventsWithTickets.length).to.equal(2);
      expect(eventsWithTickets[0]).to.equal(1);
      expect(eventsWithTickets[1]).to.equal(2);
    });

    it("Should return all events registered for by a user", async function () {
      const {
        ticketCity,
        organizer,
        attendee1,
        attendee2,
        eventParams,
        regularTicketFee,
      } = await loadFixture(deployAndSetupFixture);

      // Create events
      await ticketCity.connect(organizer).createEvent(
        "Event 1",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );
      await ticketCity
        .connect(organizer)
        .createTicket(1, 0, 0, "ipfs://free-ticket");

      await ticketCity.connect(organizer).createEvent(
        "Event 2",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );
      await ticketCity
        .connect(organizer)
        .createTicket(2, 1, regularTicketFee, "ipfs://regular-ticket");

      // Register for events
      await ticketCity.connect(attendee1).purchaseTicket(1, 0); // Free event
      await ticketCity
        .connect(attendee1)
        .purchaseTicket(2, 1, { value: regularTicketFee }); // Paid event
      await ticketCity.connect(attendee2).purchaseTicket(1, 0); // Only free event

      // Get registered events for attendee1
      const attendee1Events = await ticketCity.allEventsRegisteredForByAUser(
        attendee1.address
      );
      expect(attendee1Events.length).to.equal(2);
      expect(attendee1Events[0]).to.equal(1);
      expect(attendee1Events[1]).to.equal(2);

      // Get registered events for attendee2
      const attendee2Events = await ticketCity.allEventsRegisteredForByAUser(
        attendee2.address
      );
      expect(attendee2Events.length).to.equal(1);
      expect(attendee2Events[0]).to.equal(1);
    });

    it("Should return all valid events with tickets", async function () {
      const { ticketCity, organizer, eventParams, regularTicketFee } =
        await loadFixture(deployAndSetupFixture);

      // Create events with tickets
      await ticketCity.connect(organizer).createEvent(
        "Valid Event 1",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );
      await ticketCity
        .connect(organizer)
        .createTicket(1, 0, 0, "ipfs://free-ticket");

      await ticketCity.connect(organizer).createEvent(
        "Valid Event 2",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );
      await ticketCity
        .connect(organizer)
        .createTicket(2, 1, regularTicketFee, "ipfs://regular-ticket");

      // Create event without ticket
      await ticketCity.connect(organizer).createEvent(
        "Event Without Ticket",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );

      // Create event with ticket that has ended - Fix the date issue
      const currentTime = await time.latest();
      const pastStartDate = currentTime + time.duration.days(1); // Set to future
      const pastEndDate = pastStartDate + time.duration.days(2); // Set to future

      await ticketCity.connect(organizer).createEvent(
        "Expired Event",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        pastStartDate,
        pastEndDate,
        eventParams.expectedAttendees,
        0 // FREE
      );
      await ticketCity
        .connect(organizer)
        .createTicket(4, 0, 0, "ipfs://expired-ticket");

      // Now manually set the time to after the event has ended
      await time.increaseTo(pastEndDate + time.duration.days(1));

      // Get all valid events
      const validEvents = await ticketCity.getAllValidEvents();
      expect(validEvents.length).to.equal(2);
      expect(validEvents[0]).to.equal(1);
      expect(validEvents[1]).to.equal(2);
    });

    it("Should return revenue release details", async function () {
      const {
        ticketCity,
        organizer,
        attendee1,
        eventParams,
        regularTicketFee,
      } = await loadFixture(deployAndSetupFixture);

      // Create paid event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );

      // Create regular ticket
      await ticketCity
        .connect(organizer)
        .createTicket(1, 1, regularTicketFee, "ipfs://regular-ticket");

      // Purchase ticket
      await ticketCity
        .connect(attendee1)
        .purchaseTicket(1, 1, { value: regularTicketFee });

      // Before event end
      let [canRelease, attendanceRate, revenue] =
        await ticketCity.canReleaseRevenue(1);
      expect(canRelease).to.equal(false);
      expect(attendanceRate).to.equal(0);
      expect(revenue).to.equal(0);

      // Move time to event start and verify attendance
      await time.increaseTo(eventParams.startDate);
      await ticketCity.connect(attendee1).verifyAttendance(1);

      // Move time past event end
      await time.increaseTo(eventParams.endDate + 1);

      // After event end with 100% attendance
      [canRelease, attendanceRate, revenue] =
        await ticketCity.canReleaseRevenue(1);
      expect(canRelease).to.equal(true);
      expect(attendanceRate).to.equal(100);
      expect(revenue).to.equal(regularTicketFee);
    });

    it("Should return events requiring manual release", async function () {
      const {
        ticketCity,
        owner,
        organizer,
        attendee1,
        attendee2,
        eventParams,
        regularTicketFee,
      } = await loadFixture(deployAndSetupFixture);

      // Create paid event
      await ticketCity.connect(organizer).createEvent(
        eventParams.title,
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );

      // Create regular ticket
      await ticketCity
        .connect(organizer)
        .createTicket(1, 1, regularTicketFee, "ipfs://regular-ticket");

      // Purchase tickets (2 attendees)
      await ticketCity
        .connect(attendee1)
        .purchaseTicket(1, 1, { value: regularTicketFee });
      await ticketCity
        .connect(attendee2)
        .purchaseTicket(1, 1, { value: regularTicketFee });

      // Move time to event start and verify only one attendee (50% attendance)
      await time.increaseTo(eventParams.startDate);
      await ticketCity.connect(attendee1).verifyAttendance(1);

      // Move time past event end
      await time.increaseTo(eventParams.endDate + 1);

      // Check events requiring manual release
      const [eventIds, attendanceRates, revenues] = await ticketCity
        .connect(owner)
        .getEventsRequiringManualRelease([1]);
      expect(eventIds.length).to.equal(1);
      expect(eventIds[0]).to.equal(1);
      expect(attendanceRates[0]).to.equal(50); // 50% attendance (below 60% threshold)
      expect(revenues[0]).to.equal(regularTicketFee * BigInt(2));
    });

    it("Should return user's ticket details", async function () {
      const {
        ticketCity,
        organizer,
        attendee1,
        eventParams,
        regularTicketFee,
        vipTicketFee,
      } = await loadFixture(deployAndSetupFixture);

      // Create free event
      await ticketCity.connect(organizer).createEvent(
        "Free Event",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        0 // FREE
      );
      await ticketCity
        .connect(organizer)
        .createTicket(1, 0, 0, "ipfs://free-ticket");

      // Create paid event
      await ticketCity.connect(organizer).createEvent(
        "Paid Event",
        eventParams.desc,
        eventParams.imageUri,
        eventParams.location,
        eventParams.startDate,
        eventParams.endDate,
        eventParams.expectedAttendees,
        1 // PAID
      );
      await ticketCity
        .connect(organizer)
        .createTicket(2, 1, regularTicketFee, "ipfs://regular-ticket");
      await ticketCity
        .connect(organizer)
        .createTicket(2, 2, vipTicketFee, "ipfs://vip-ticket");

      // Purchase tickets
      await ticketCity.connect(attendee1).purchaseTicket(1, 0); // Free ticket
      await ticketCity
        .connect(attendee1)
        .purchaseTicket(2, 2, { value: vipTicketFee }); // VIP ticket

      // Check ticket details
      const [eventIds, ticketTypes, verified] = await ticketCity
        .connect(attendee1)
        .getMyTickets();
      expect(eventIds.length).to.equal(2);
      expect(ticketTypes.length).to.equal(2);
      expect(verified.length).to.equal(2);

      // Verify correct event IDs
      expect(eventIds.includes(BigInt(1))).to.be.true;
      expect(eventIds.includes(BigInt(2))).to.be.true;

      // Verify correct ticket types
      const eventId1Index = eventIds.findIndex((id) => id.toString() === "1");
      const eventId2Index = eventIds.findIndex((id) => id.toString() === "2");

      expect(ticketTypes[eventId1Index]).to.equal("FREE");
      expect(ticketTypes[eventId2Index]).to.equal("VIP");

      // Verify attendance status (both should be false initially)
      expect(verified[eventId1Index]).to.be.false;
      expect(verified[eventId2Index]).to.be.false;

      // Verify attendance for one event
      await time.increaseTo(eventParams.startDate);
      await ticketCity.connect(attendee1).verifyAttendance(1);

      // Check updated verification status
      const [updatedEventIds, updatedTicketTypes, updatedVerified] =
        await ticketCity.connect(attendee1).getMyTickets();
      const updatedEventId1Index = updatedEventIds.findIndex(
        (id) => id.toString() === "1"
      );
      const updatedEventId2Index = updatedEventIds.findIndex(
        (id) => id.toString() === "2"
      );

      expect(updatedVerified[updatedEventId1Index]).to.be.true;
      expect(updatedVerified[updatedEventId2Index]).to.be.false;
    });
  });
});
