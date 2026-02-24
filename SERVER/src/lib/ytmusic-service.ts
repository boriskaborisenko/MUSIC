import YTMusic from "ytmusic-api";

import { config } from "../config";
import { AppError } from "./app-error";

export type SearchType = "all" | "songs" | "videos" | "artists" | "albums" | "playlists";

class YTMusicService {
  private readonly client = new YTMusic();
  private initPromise: Promise<void> | null = null;
  private initialized = false;

  public isInitialized() {
    return this.initialized;
  }

  private async ensureInitialized() {
    if (this.initialized) {
      return;
    }

    if (!this.initPromise) {
      this.initPromise = (async () => {
        const initializedClient = await this.client.initialize({
          cookies: config.ytmusic.cookies,
          GL: config.ytmusic.gl,
          HL: config.ytmusic.hl,
        });

        if (!initializedClient) {
          throw new AppError(502, "Failed to initialize ytmusic-api client", "YTMUSIC_INIT_FAILED");
        }

        this.initialized = true;
      })().catch((error) => {
        this.initPromise = null;
        throw error;
      });
    }

    await this.initPromise;
  }

  async getSearchSuggestions(query: string) {
    await this.ensureInitialized();
    return this.client.getSearchSuggestions(query);
  }

  async search(query: string, type: SearchType = "all") {
    await this.ensureInitialized();

    switch (type) {
      case "songs":
        return this.client.searchSongs(query);
      case "videos":
        return this.client.searchVideos(query);
      case "artists":
        return this.client.searchArtists(query);
      case "albums":
        return this.client.searchAlbums(query);
      case "playlists":
        return this.client.searchPlaylists(query);
      case "all":
      default:
        return this.client.search(query);
    }
  }

  async getHomeSections() {
    await this.ensureInitialized();
    return this.client.getHomeSections();
  }

  async getSong(videoId: string) {
    await this.ensureInitialized();
    return this.client.getSong(videoId);
  }

  async getUpNexts(videoId: string) {
    await this.ensureInitialized();
    return this.client.getUpNexts(videoId);
  }

  async getLyrics(videoId: string) {
    await this.ensureInitialized();
    return this.client.getLyrics(videoId);
  }

  async getVideo(videoId: string) {
    await this.ensureInitialized();
    return this.client.getVideo(videoId);
  }

  async getArtist(artistId: string) {
    await this.ensureInitialized();
    return this.client.getArtist(artistId);
  }

  async getArtistSongs(artistId: string) {
    await this.ensureInitialized();
    return this.client.getArtistSongs(artistId);
  }

  async getArtistAlbums(artistId: string) {
    await this.ensureInitialized();
    return this.client.getArtistAlbums(artistId);
  }

  async getAlbum(albumId: string) {
    await this.ensureInitialized();
    return this.client.getAlbum(albumId);
  }

  async getPlaylist(playlistId: string) {
    await this.ensureInitialized();
    return this.client.getPlaylist(playlistId);
  }

  async getPlaylistVideos(playlistId: string) {
    await this.ensureInitialized();
    return this.client.getPlaylistVideos(playlistId);
  }
}

export const ytmusicService = new YTMusicService();
